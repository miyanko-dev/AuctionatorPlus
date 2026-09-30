local _, AP = ...

-- "Show Similar Items / Bags": while gear or a container sits in the sale slot, browse the auction house for comparable listings and merge one row per comparable into the selling tab's current-prices listing, cheapest listing and total available per item
AP.SimilarItems = {}

-- Trade goods and unequippable items report an empty equipLoc
local NON_GEAR_SLOTS = {
    [""] = true,
    INVTYPE_BAG = true,
    INVTYPE_QUIVER = true,
    INVTYPE_AMMO = true,
    INVTYPE_NON_EQUIP = true,
    INVTYPE_NON_EQUIP_IGNORE = true,
}

-- Robes share the chest slot and main- or off-hand-only weapons the generic one-hand slot
local function normalizeSlot(equipLoc)
    if equipLoc == "INVTYPE_ROBE" then return "INVTYPE_CHEST" end
    if equipLoc == "INVTYPE_WEAPONMAINHAND" or equipLoc == "INVTYPE_WEAPONOFFHAND" then
        return "INVTYPE_WEAPON"
    end
    return equipLoc
end

-- Auction browse inventory types per equip location; slots absent here filter by subclass alone
local SLOT_INVENTORY_TYPES = {
    INVTYPE_HEAD = Enum.InventoryType.IndexHeadType,
    INVTYPE_NECK = Enum.InventoryType.IndexNeckType,
    INVTYPE_SHOULDER = Enum.InventoryType.IndexShoulderType,
    INVTYPE_BODY = Enum.InventoryType.IndexBodyType,
    INVTYPE_WAIST = Enum.InventoryType.IndexWaistType,
    INVTYPE_LEGS = Enum.InventoryType.IndexLegsType,
    INVTYPE_FEET = Enum.InventoryType.IndexFeetType,
    INVTYPE_WRIST = Enum.InventoryType.IndexWristType,
    INVTYPE_HAND = Enum.InventoryType.IndexHandType,
    INVTYPE_FINGER = Enum.InventoryType.IndexFingerType,
    INVTYPE_TRINKET = Enum.InventoryType.IndexTrinketType,
    INVTYPE_CLOAK = Enum.InventoryType.IndexCloakType,
    INVTYPE_HOLDABLE = Enum.InventoryType.IndexHoldableType,
}

local CHECKBOX_TEXT = {
    gear = {
        label = "Show Similar Items",
        tooltip = "When a piece of gear is placed for sale, also list the cheapest auction of every item with the same slot and armor or weapon type within %d levels of its required level. Matches must carry every stat of the item being sold, each within %d%% of its amount, with a stat count within %d of it. Weapons must additionally deal within %d%% of its damage per second. Click a similar auction to take its unit price for your listing.",
    },
    bag = {
        label = "Show Similar Bags",
        tooltip = "When a container is placed for sale, also list the cheapest auction of every container with the same number of slots. Click a similar auction to take its unit price for your listing.",
    },
}

-- Gear and bags remember their own choice
local SETTING_KEYS = { gear = "showSimilarItems", bag = "showSimilarBags" }

-- Browse pages keep coming for large categories; stop asking past this many rows
local MAX_BROWSE_ROWS = 600

-- Merge no later than this after the browse finished, even if the item's own search never reported back
local MERGE_FALLBACK_SECONDS = 3

-- Evaluate with the item data that arrived by then, so one item the server never sends cannot hold back every row
local ITEM_LOAD_TIMEOUT_SECONDS = 5

local BROWSE_EVENTS = {
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
    "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "AUCTION_HOUSE_BROWSE_FAILURE",
}

-- profile describes the sale item while comparables are gathered; a new sale search replaces it, which retires every callback still holding the old one. browsing is true while the browse listener pages results, waiting while the browse waits for a shopping search or an incremental scan to end
local watch = {
    saleLink = nil,
    saleKind = nil,
    profile = nil,
    browsing = false,
    waiting = false,
}

local browseFrame = CreateFrame("Frame")

-- The Show Similar checkbox under the bag panel, created on the first AH open
local similarCheck

-- ===== Sale item =====
-- Containers and quivers count as bags, everything equippable as gear
local function kindOf(itemLink)
    local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(itemLink)
    if classID == Enum.ItemClass.Container or classID == Enum.ItemClass.Quiver then
        return "bag"
    end
    if type(equipLoc) == "string" and not NON_GEAR_SLOTS[equipLoc] then
        return "gear"
    end
    return nil
end

-- Whether the player wants comparables for this kind of sale item
local function isWanted(kind)
    return kind ~= nil and AP.DB()[SETTING_KEYS[kind]] == true
end

-- Server browse filters from class, subclass and slot; chest and robe listings form one pool like the normalized slot
local function categoryFilters(classID, subClassID, equipLoc)
    if classID ~= Enum.ItemClass.Armor then
        return { { classID = classID, subClassID = subClassID } }
    end
    if equipLoc == "INVTYPE_CHEST" or equipLoc == "INVTYPE_ROBE" then
        return {
            { classID = classID, subClassID = subClassID, inventoryType = Enum.InventoryType.IndexChestType },
            { classID = classID, subClassID = subClassID, inventoryType = Enum.InventoryType.IndexRobeType },
        }
    end
    return { { classID = classID, subClassID = subClassID, inventoryType = SLOT_INVENTORY_TYPES[equipLoc] } }
end

-- Comparison profile of the sale item, synchronous since the slotted item sits in the bags and is cached; nil for unsupported or uncached items
local function profileFor(itemLink)
    local kind = kindOf(itemLink)
    local itemID, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemLink)
    local itemText = AP.ItemStats.Text(itemLink)
    if not kind or not itemID or not itemText then return nil end

    if kind == "bag" then
        local slotCount = AP.ItemStats.ParseSlotCount(itemText)
        if not slotCount then return nil end
        return {
            kind = "bag",
            itemID = itemID,
            itemLink = itemLink,
            slotCount = slotCount,
            filters = { { classID = classID } },
        }
    end

    return {
        kind = "gear",
        itemID = itemID,
        itemLink = itemLink,
        equipLoc = normalizeSlot(equipLoc),
        subClassID = subClassID,
        requiredLevel = AP.ItemStats.RequiredLevel(itemLink) or 0,
        filters = categoryFilters(classID, subClassID, equipLoc),

        -- Weapons gate on the DPS band before the stat set; a weapon with no parseable DPS line skips the gate
        dps = classID == Enum.ItemClass.Weapon and AP.ItemStats.ParseDPS(itemText) or nil,
        statSet = AP.ItemStats.FullStatSet(itemText),
    }
end

-- Required-level band for the server-side filter, only when the whole band sits above zero, since a level range drops "no level requirement" listings
local function levelRange(profile)
    local tolerance = AP.DB().levelTolerance
    local level = profile.requiredLevel
    if level and level > tolerance then
        return level - tolerance, level + tolerance
    end
    return nil, nil
end

-- ===== Matching =====
-- Instant check that needs no item data: same slot and armor or weapon type, or any container for a bag
local function sameType(profile, itemRef)
    local _, _, _, equipLoc, _, classID, subClassID = AP.ItemStats.InstantInfo(itemRef)
    if profile.kind == "bag" then
        return classID == Enum.ItemClass.Container or classID == Enum.ItemClass.Quiver
    end
    return normalizeSlot(equipLoc) == profile.equipLoc and subClassID == profile.subClassID
end

-- Checks that need cached item data: required level, for weapons the DPS band, then every stat of the sale item within its value band with a stat count within the tolerance; bags must hold the same number of slots
local function matches(profile, itemRef)
    local itemText = AP.ItemStats.Text(itemRef)
    if not itemText then return false end

    if profile.kind == "bag" then
        return AP.ItemStats.ParseSlotCount(itemText) == profile.slotCount
    end

    local db = AP.DB()
    local level = AP.ItemStats.RequiredLevel(itemRef) or 0
    if math.abs(level - profile.requiredLevel) > db.levelTolerance then return false end

    if profile.dps then
        local dps = AP.ItemStats.ParseDPS(itemText)
        if not dps or math.abs(dps - profile.dps) > profile.dps * db.dpsTolerancePct / 100 then return false end
    end

    local stats = AP.ItemStats.FullStatSet(itemText)
    if not AP.ItemStats.Covers(stats, profile.statSet, db.statValueTolerance) then return false end
    return math.abs(AP.ItemStats.Count(stats) - AP.ItemStats.Count(profile.statSet)) <= db.statCountTolerance
end

-- ===== Checkbox =====
-- Label and saved state for the sale item's kind; hidden for items without comparables
local function showCheckbox()
    if not similarCheck then return end

    local text = CHECKBOX_TEXT[watch.saleKind]
    if not text then
        similarCheck:Hide()
        return
    end
    similarCheck.Text:SetText(text.label)
    similarCheck:SetChecked(isWanted(watch.saleKind))
    similarCheck:Show()
end

local function showTooltip(self)
    local text = CHECKBOX_TEXT[watch.saleKind]
    if not text then return end
    local db = AP.DB()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, text.label)
    GameTooltip_AddHighlightLine(GameTooltip, text.tooltip:format(db.levelTolerance, db.statValueTolerance, db.statCountTolerance, db.dpsTolerancePct), true)
    GameTooltip:Show()
end

local function trackSaleItem(itemLink)
    watch.saleLink = itemLink
    watch.saleKind = itemLink and kindOf(itemLink) or nil
    showCheckbox()
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
    return itemKey.itemID ~= profile.itemID and sameType(profile, itemKey)
end

local function finishBrowse(profile, results)
    local candidates = {}
    for _, result in ipairs(results) do
        if isCandidate(profile, result.itemKey) then
            candidates[#candidates + 1] = result
        end
    end

    -- Stats and levels need every candidate's item data cached; runs once, on the last load or at the timeout, where uncached candidates simply do not match
    local remaining = #candidates
    local evaluated = false
    local function evaluate()
        if evaluated or watch.profile ~= profile then return end
        evaluated = true
        local rows = {}
        for _, result in ipairs(candidates) do
            if matches(profile, result.itemKey) then
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
    C_Timer.After(ITEM_LOAD_TIMEOUT_SECONDS, evaluate)
    for _, result in ipairs(candidates) do
        Item:CreateFromItemID(result.itemKey.itemID):ContinueOnItemLoad(function()
            remaining = remaining - 1
            if remaining == 0 then evaluate() end
        end)
    end
end

-- ===== Browse query =====
local function stopBrowse()
    watch.browsing = false
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

-- Auctionator's shopping search and its incremental full scan page the client's single browse result set, which a comparables browse would replace
local function browseBusy()
    local scanFrame = Auctionator.State.IncrementalScanFrameRef
    local shoppingFrame = AuctionatorShoppingFrame
    return (scanFrame ~= nil and scanFrame.doingFullScan == true)
        or (shoppingFrame ~= nil and shoppingFrame.searchRunning == true)
end

-- Browse the sale item's category in the background; the query joins Auctionator's throttle queue behind the item's own search
local function startBrowse(profile)
    watch.profile = profile
    watch.browsing = true
    local minLevel, maxLevel = levelRange(profile)
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
    watch.waiting = false
    stopBrowse()
end

-- Every sell search of the slotted item restarts the comparables, so Refresh and re-drops stay in step with the listing; while another browse owns the result set the profile waits for it to end
local function onSellSearch(itemLink)
    cancel()
    trackSaleItem(itemLink)
    if not isWanted(watch.saleKind) then return end

    local profile = profileFor(itemLink)
    if not profile then return end
    if browseBusy() then
        watch.profile = profile
        watch.waiting = true
    else
        startBrowse(profile)
    end
end

-- Marks that the listing has its own results, so merged rows can no longer be wiped by them
local function onNativeResults(itemID)
    local profile = watch.profile
    if profile and profile.itemID == itemID then
        profile.nativeReady = true
        if profile.rows then scheduleMerge(profile) end
    end
end

-- A browse still paging gives way to one Auctionator starts and waits for it to end; finished comparables stay, since their rows no longer need the result set
local function yieldBrowse()
    if not watch.browsing then return end
    stopBrowse()
    watch.waiting = true
end

-- Run the waiting browse once the search or scan it waited for has ended, a frame later because a new shopping search first ends the old one. Only while the Selling tab is open; the profile is always the selected item's, since a new selection or a cleared slot replaces or drops it
local function resumeBrowse()
    C_Timer.After(0, function()
        if not watch.waiting or browseBusy() or not AuctionatorSellingFrame:IsVisible() then return end
        watch.waiting = false
        startBrowse(watch.profile)
    end)
end

AP.Bridge.Listen({
    Auctionator.Selling.Events.SellSearchStart,
    Auctionator.Selling.Events.ClearBagItem,
    Auctionator.AH.Events.ItemSearchResultsReady,
    Auctionator.AH.Events.CommoditySearchResultsReady,
    Auctionator.Shopping.Tab.Events.SearchStart,
    Auctionator.Shopping.Tab.Events.SearchEnd,
    Auctionator.IncrementalScan.Events.ScanStart,
    Auctionator.IncrementalScan.Events.ScanComplete,
    Auctionator.IncrementalScan.Events.ScanFailed,
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
    elseif eventName == Auctionator.Shopping.Tab.Events.SearchStart or eventName == Auctionator.IncrementalScan.Events.ScanStart then
        yieldBrowse()
    else
        resumeBrowse()
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

    local check = CreateFrame("CheckButton", "AuctionatorPlusShowSimilar", sellingFrame, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", inset, "BOTTOMLEFT", 0, -1)
    check:SetScript("OnClick", function(self)
        if not watch.saleKind then return end
        AP.DB()[SETTING_KEYS[watch.saleKind]] = self:GetChecked() and true or false

        -- Re-running the item's own search rebuilds the listing with or without comparables
        if watch.saleLink then AP.Bridge.RefreshSellSearch() end
    end)
    check:SetScript("OnEnter", showTooltip)
    check:SetScript("OnLeave", GameTooltip_Hide)

    -- Leaving the tab ends a browse no one would see and frees the result set for the other tabs
    sellingFrame:HookScript("OnHide", cancel)

    similarCheck = check
    showCheckbox()
    return true
end
