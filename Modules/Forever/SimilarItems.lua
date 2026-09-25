local _, AP = ...

-- Forever half of Show Similar Items: while gear or a container sits in the sale slot, browse the auction house for comparable listings and merge one row per comparable into the current-prices listing, cheapest listing and total available per item
local Similar = AP.SimilarItems

-- Browse pages keep coming for large categories; stop asking past this many rows
local MAX_BROWSE_ROWS = 600

-- Merge no later than this after the browse finished, even if the item's own search never reported back
local MERGE_FALLBACK_SECONDS = 3

local BROWSE_EVENTS = {
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
    "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "AUCTION_HOUSE_BROWSE_FAILURE",
}

-- profile describes the sale item while comparables are gathered; a new sale search replaces it, which retires every callback still holding the old one
local watch = {
    saleLink = nil,
    saleKind = nil,
    profile = nil,
}

local browseFrame = CreateFrame("Frame")

-- The Show Similar checkbox under the bag panel, created on the first AH open
local similarCheck

local function trackSaleItem(itemLink)
    watch.saleLink = itemLink
    watch.saleKind = itemLink and Similar.KindOf(itemLink) or nil
    Similar.ShowCheckbox(watch.saleKind)
end

-- ===== Merging into the current-prices listing =====
-- Vanilla random suffixes are fixed per suffix id, so the item string names the exact item; the cached hyperlink lets chat links and previews work on the row
local function linkFor(itemKey)
    local itemString = ("item:%d:0:0:0:0:0:%d"):format(itemKey.itemID, itemKey.itemSuffix or 0)
    return select(2, C_Item.GetItemInfo(itemString)) or itemString
end

-- One row per comparable in the shape of Auctionator's sell-search rows; no owners, so the row tooltip shows the item alone
local function rowFor(result)
    local itemKey = result.itemKey
    return {
        apComparable = true,
        itemKey = itemKey,
        itemLink = linkFor(itemKey),
        auctionID = "ap:" .. AP.Bridge.ItemKeyString(itemKey),
        price = result.minPrice,
        quantity = result.totalQuantity,
        quantityFormatted = FormatLargeNumber(result.totalQuantity),
        level = itemKey.itemLevel or 0,
        levelPretty = tostring(itemKey.itemLevel or 0),
        otherSellers = "",
        timeLeft = 0,
        timeLeftPretty = "",
        owned = "",
        itemType = Auctionator.Constants.ITEM_TYPES.ITEM,
        canBuy = false,
    }
end

local function currentPricesProvider()
    return AuctionatorSellingFrame and AuctionatorSellingFrame.CurrentPricesProvider
end

-- Append the rows unless the listing meanwhile shows another item; the provider dedups by auction id, so a repeat merge after its reset is safe
local function merge(profile)
    local provider = currentPricesProvider()
    local expected = provider and provider.expectedItemKey
    if not expected or expected.itemID ~= profile.itemID or not profile.rows or #profile.rows == 0 then return end
    provider:AppendEntries(profile.rows, true)
end

-- The listing resets itself when the sale item's own results land, so rows are merged a frame later and merged again if those results arrive afterwards
local function scheduleMerge(profile)
    C_Timer.After(0, function()
        if watch.profile == profile then merge(profile) end
    end)
end

-- The sale item's own suffix variants already answer its bare-key sell search
local function isCandidate(profile, itemKey)
    return itemKey.itemID ~= profile.itemID and Similar.SameType(profile, itemKey)
end

local function finishBrowse(profile, results)
    local candidates = {}
    for _, result in ipairs(results) do
        if isCandidate(profile, result.itemKey) then
            candidates[#candidates + 1] = result
        end
    end

    -- Stats and levels need every candidate's item data cached
    local remaining = #candidates
    local function evaluate()
        if watch.profile ~= profile then return end
        local rows = {}
        for _, result in ipairs(candidates) do
            if Similar.Matches(profile, result.itemKey) then
                rows[#rows + 1] = rowFor(result)
            end
        end
        profile.rows = rows
        if profile.nativeReady then
            scheduleMerge(profile)
        else
            C_Timer.After(MERGE_FALLBACK_SECONDS, function() scheduleMerge(profile) end)
        end
    end
    if remaining == 0 then
        evaluate()
        return
    end
    for _, result in ipairs(candidates) do
        Item:CreateFromItemID(result.itemKey.itemID):ContinueOnItemLoad(function()
            remaining = remaining - 1
            if remaining == 0 then evaluate() end
        end)
    end
end

-- ===== Browse query =====
local function stopBrowse()
    browseFrame:UnregisterAllEvents()
end

browseFrame:SetScript("OnEvent", function(_, event)
    local profile = watch.profile
    if not profile or event == "AUCTION_HOUSE_BROWSE_FAILURE" then
        stopBrowse()
        return
    end

    local results = C_AuctionHouse.GetBrowseResults()
    if AP.Bridge.BrowseFinished() or #results >= MAX_BROWSE_ROWS then
        stopBrowse()
        finishBrowse(profile, results)
    else
        AP.Bridge.BrowseMore()
    end
end)

-- Browse the sale item's category in the background; the query joins Auctionator's throttle queue behind the item's own search
local function startBrowse(profile)
    watch.profile = profile
    local minLevel, maxLevel = Similar.LevelRange(profile)
    FrameUtil.RegisterFrameForEvents(browseFrame, BROWSE_EVENTS)
    AP.Bridge.Browse({
        searchString = "",
        minLevel = minLevel,
        maxLevel = maxLevel,
        itemClassFilters = profile.filters,
        sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } },
    })
end

local function cancel()
    watch.profile = nil
    stopBrowse()
end

-- Every sell search of the slotted item restarts the comparables, so Refresh and re-drops stay in step with the listing
local function onSellSearch(itemLink)
    cancel()
    trackSaleItem(itemLink)
    if not Similar.IsWanted(watch.saleKind) then return end

    local profile = Similar.ProfileFor(itemLink)
    if profile then startBrowse(profile) end
end

-- Marks that the listing has its own results, so merged rows can no longer be wiped by them
local function onNativeResults(itemID)
    local profile = watch.profile
    if profile and profile.itemID == itemID then
        profile.nativeReady = true
        if profile.rows then scheduleMerge(profile) end
    end
end

AP.Bridge.Listen({
    Auctionator.Selling.Events.SellSearchStart,
    Auctionator.Selling.Events.ClearBagItem,
    Auctionator.AH.Events.ItemSearchResultsReady,
    Auctionator.AH.Events.CommoditySearchResultsReady,
}, function(_, eventName, first, second)
    if eventName == Auctionator.Selling.Events.SellSearchStart then
        onSellSearch(second)
    elseif eventName == Auctionator.Selling.Events.ClearBagItem then
        cancel()
        trackSaleItem(nil)
    elseif eventName == Auctionator.AH.Events.ItemSearchResultsReady then
        onNativeResults(first.itemID)
    elseif eventName == Auctionator.AH.Events.CommoditySearchResultsReady then
        onNativeResults(first)
    end
end)

-- A comparable is no auction, so its clicks never reach Auctionator's cancel and buy shortcuts: modified clicks link or preview the item, a left click hands over its exact price. Replaced on the mixin before the AH creates any rows
local baseRowClick = AuctionatorSellSearchRowMixin.OnClick
function AuctionatorSellSearchRowMixin:OnClick(button, ...)
    local row = self.rowData
    if not (row and row.apComparable) then
        return baseRowClick(self, button, ...)
    end
    if IsModifiedClick("CHATLINK") or IsModifiedClick("DRESSUP") then
        HandleModifiedItemClick(row.itemLink)
    elseif button == "LeftButton" then
        AP.Bridge.SelectPrice(row.price)
    end
end

-- Under the bag panel, in the strip the price mini-tabs leave free on the left
function AP.SimilarItems.Ensure()
    if similarCheck then return true end
    local sellingFrame = AuctionatorSellingFrame
    local inset = sellingFrame and sellingFrame.BagInset
    if not inset then return false end

    -- Re-running the item's own search rebuilds the listing with or without comparables
    similarCheck = Similar.CreateCheckbox(sellingFrame, function()
        if watch.saleLink then AP.Bridge.RefreshSellSearch() end
    end)
    similarCheck:SetPoint("TOPLEFT", inset, "BOTTOMLEFT", 0, -1)
    return true
end
