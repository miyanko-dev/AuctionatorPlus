local _, AP = ...

-- "Sale Scan" on Forever: one live price search per distinct bag item, sequentially through Auctionator's throttle queue, recording each cheapest listing in Auctionator's price database so the Relative Value and the bag glow reflect current prices
AP.SaleScan = {}

local BUTTON_LABEL = "Sale Scan"
local BUTTON_WIDTH = 110
local BUTTON_HEIGHT = 22
local BUTTON_GAP = 4

-- A search the server never answers is skipped after this
local QUERY_TIMEOUT_SECONDS = 8

local scanButton

-- queue holds the bag items still to scan (nil while idle), expected the item key of the in-flight search
local state = {
    queue = nil,
    total = 0,
    expected = nil,
    timeout = nil,
}

local function setLabel(text)
    if scanButton then scanButton:SetText(text) end
end

local function cancelTimeout()
    if state.timeout then
        state.timeout:Cancel()
        state.timeout = nil
    end
end

local function stop()
    if not state.queue then return end
    cancelTimeout()
    state.queue = nil
    state.expected = nil
    setLabel(BUTTON_LABEL)
end

local nextQuery

-- Gear searches with the bare key so every suffix variant answers; the cheapest result is recorded under the item's own key by Auctionator's rules
local function runQuery(item)
    local isGear = AP.Bridge.IsEquipment(item.classID)
    local itemKey = isGear and AP.Bridge.BaseItemKey(item.itemID) or C_AuctionHouse.MakeItemKey(item.itemID)
    state.expected = itemKey
    setLabel(("Scanning %d/%d"):format(state.total - #state.queue, state.total))
    if not AP.Bridge.SearchItem(itemKey, isGear) then
        nextQuery()
        return
    end
    state.timeout = C_Timer.NewTimer(QUERY_TIMEOUT_SECONDS, nextQuery)
end

nextQuery = function()
    if not state.queue then return end
    cancelTimeout()
    local item = table.remove(state.queue, 1)
    if not item then
        stop()
        return
    end
    runQuery(item)
end

local function recordItemResult(itemKey)
    if C_AuctionHouse.GetNumItemSearchResults(itemKey) == 0 then return end
    local result = C_AuctionHouse.GetItemSearchResultInfo(itemKey, 1)
    if result then
        AP.Bridge.RecordPrice(result.itemKey, result.buyoutAmount or result.bidAmount)
    end
end

local function recordCommodityResult(itemID)
    if C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID) == 0 then return end
    local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
    if result then
        AP.Bridge.RecordPrice(C_AuctionHouse.MakeItemKey(itemID), result.unitPrice)
    end
end

local function receiveEvent(_, eventName, payload)
    local expected = state.expected
    if not state.queue or not expected then return end
    if eventName == Auctionator.Selling.Events.SellSearchStart then
        -- the player selected an item; the scanner belongs to the selling flow now
        stop()
        return
    end

    if eventName == Auctionator.AH.Events.ItemSearchResultsReady then
        if type(payload) ~= "table" or not AP.Bridge.SameItemKey(payload, expected) then return end
        recordItemResult(payload)
    elseif eventName == Auctionator.AH.Events.CommoditySearchResultsReady then
        if payload ~= expected.itemID then return end
        recordCommodityResult(payload)
    else
        return
    end

    AP.BagGlow.Repaint()
    nextQuery()
end

-- Registered for the whole session; the handler is inert while no scan runs
AP.Bridge.Listen({
    Auctionator.AH.Events.ItemSearchResultsReady,
    Auctionator.AH.Events.CommoditySearchResultsReady,
    Auctionator.Selling.Events.SellSearchStart,
}, receiveEvent)

-- Distinct auctionable items shown in the bag panel
local function bagItems()
    local listing = AuctionatorSellingFrame and AuctionatorSellingFrame.BagListing
    local view = listing and listing.View
    if not view or type(view.itemMap) ~= "table" then return {} end

    local seen, items = {}, {}
    for _, group in pairs(view.itemMap) do
        for _, button in pairs(group) do
            local info = type(button) == "table" and button.itemInfo
            if info and info.itemID and not seen[info.itemID] then
                seen[info.itemID] = true
                items[#items + 1] = info
            end
        end
    end
    return items
end

local function start()
    if state.queue then return end
    local items = bagItems()
    if #items == 0 then return end

    state.queue = items
    state.total = #items
    nextQuery()
end

-- Left of the selling tab's Full Scan button
function AP.SaleScan.Ensure()
    if scanButton then return true end
    local sellingFrame = AuctionatorSellingFrame
    local fullScanButton = AP.sellingScanButton
    if not sellingFrame or not fullScanButton then return false end

    local button = CreateFrame("Button", "AuctionatorPlusSaleScanButton", sellingFrame, "UIPanelButtonTemplate")
    button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    button:SetPoint("RIGHT", fullScanButton, "LEFT", -BUTTON_GAP, 0)
    button:SetText(BUTTON_LABEL)

    button:SetScript("OnClick", function()
        if state.queue then stop() else start() end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip_SetTitle(GameTooltip, BUTTON_LABEL)
        GameTooltip_AddHighlightLine(GameTooltip, "Runs one live price search for every item in the bag panel, so the Relative Value and the item glows use current auction prices. Click again to cancel. Steps aside as soon as you select an item to sell.", true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    sellingFrame:HookScript("OnHide", stop)

    scanButton = button
    return true
end
