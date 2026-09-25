local _, AP = ...

-- "Sale Scan" on Era: a button right of the AH money frame in the selling tab. One click runs a live exact-name search per distinct bag-listing item, the same sequential term scan a shopping list runs, first page only since only the lowest price matters, feeding Auctionator's price database so the Relative Value and the bag glow reflect current prices
AP.SaleScan = {}

local BUTTON_LABEL = "Sale Scan"
local CANCEL_LABEL = "Cancel Scan"
local BUTTON_WIDTH = 110
local BUTTON_HEIGHT = 22

-- The bag view fills asynchronously after the tab opens
local RETRY_SECONDS = 0.5
local MAX_RETRIES = 6

-- Shown as the list name in Auctionator's search-progress line
local SCAN_LIST_NAME = "Bags"

local SCAN_EVENTS = {
    Auctionator.AH.Events.ScanResultsUpdate,
    Auctionator.AH.Events.ScanAborted,
    Auctionator.AH.Events.ThrottleUpdate,
    Auctionator.Selling.Events.StartFakeBuyLoading,
}

-- queue holds the item names still to scan (nil while idle) and entries the in-flight query's results; aborting marks a ScanAborted we caused ourselves
local state = {
    queue = nil,
    total = 0,
    entries = nil,
    scanning = false,
    aborting = false,
}
local listener, scanButton

local function spinnerListing()
    local buyFrame = AuctionatorSellingFrame and AuctionatorSellingFrame.BuyFrame
    local currentPrices = buyFrame and buyFrame.CurrentPrices
    return currentPrices and currentPrices.SearchResultsListing
end

-- Same progress line a shopping list scan shows ("Search for item X/Y in ...")
local function setProgressText()
    local listing = spinnerListing()
    local resultsText = listing and listing.ScrollArea and listing.ScrollArea.ResultsText
    if not resultsText then return end
    resultsText:SetText(AP.Bridge.SearchStatus(state.total - #state.queue, state.total, SCAN_LIST_NAME))
end

-- The current-prices listing carries the same spinner the shopping results use; borrow it for scan progress. An empty panel's "No results" would sit under the spinner, so it is stashed and put back on stop, and the progress text is restored since the listing reuses it for its own searches
local hidNoResults = false
local savedResultsText

local function setSpinnerShown(shown)
    local listing = spinnerListing()
    if not listing then return end

    local scrollArea = listing.ScrollArea or {}
    local noResults = scrollArea.NoResultsText
    local resultsText = scrollArea.ResultsText
    if shown then
        if resultsText then savedResultsText = resultsText:GetText() end
        if listing.EnableSpinner then listing:EnableSpinner() end
        if noResults and noResults:IsShown() then
            hidNoResults = true
            noResults:Hide()
        end
        return
    end

    if listing.DisableSpinner then listing:DisableSpinner() end
    if resultsText and savedResultsText then
        resultsText:SetText(savedResultsText)
        savedResultsText = nil
    end
    if hidNoResults then
        hidNoResults = false
        if noResults then noResults:Show() end
    end
end

local function stop()
    if not state.queue then return end
    AP.Bridge.Unregister(listener, SCAN_EVENTS)
    state.queue = nil
    state.entries = nil
    state.scanning = false
    state.aborting = false
    setSpinnerShown(false)
    if scanButton then scanButton:SetText(BUTTON_LABEL) end
end

-- One query at a time: the legacy scanner has no queue of its own and a second start would fail
local function nextQuery()
    if not state.queue or state.scanning then return end
    if not AP.Bridge.IsNotThrottled() then return end

    local itemName = table.remove(state.queue, 1)
    if not itemName then
        stop()
        return
    end

    setProgressText()
    state.entries = {}
    state.scanning = true
    if not AP.Bridge.Query({ searchString = itemName, isExact = true }) then stop() end
end

local function finishQuery()
    local batch = state.entries
    state.entries = nil
    state.scanning = false
    if #batch > 0 then
        AP.Bridge.RecordResults(batch)
    end
    AP.BagGlow.Repaint()
    nextQuery()
end

local function receiveEvent(_, eventName, eventData, gotAllResults)
    local events = Auctionator.AH.Events

    if eventName == events.ScanResultsUpdate then
        if not state.scanning then return end
        if type(eventData) == "table" then
            for _, entry in ipairs(eventData) do
                state.entries[#state.entries + 1] = entry
            end
        end
        if gotAllResults then
            finishQuery()
        else
            -- Pages arrive sorted by unit price, so the first already holds the cheapest; skip the rest like a shopping search without "always load more"
            state.aborting = true
            AP.Bridge.AbortQuery()
        end

    elseif eventName == events.ScanAborted then
        if state.aborting then
            state.aborting = false
            finishQuery()
        elseif state.scanning then
            -- Another search stomped ours; whatever the player started wins
            stop()
        end

    elseif eventName == events.ThrottleUpdate then
        if eventData == true then nextQuery() end

    elseif eventName == Auctionator.Selling.Events.StartFakeBuyLoading then
        -- An item entered the sale slot; leave the scanner to the selling flow
        stop()
    end
end

listener = { ReceiveEvent = receiveEvent }

local function bagItemNames()
    local listing = AuctionatorSellingFrame and AuctionatorSellingFrame.BagListing
    local view = listing and listing.View
    if not view or type(view.itemMap) ~= "table" then return {} end

    local seen, names = {}, {}
    for _, group in pairs(view.itemMap) do
        for _, button in pairs(group) do
            local itemInfo = type(button) == "table" and button.itemInfo
            if itemInfo and itemInfo.itemName and not seen[itemInfo.itemName] then
                seen[itemInfo.itemName] = true
                names[#names + 1] = itemInfo.itemName
            end
        end
    end
    return names
end

local function startScan(attempt)
    if state.queue then return end
    local sellingFrame = AuctionatorSellingFrame
    if not sellingFrame or not sellingFrame:IsVisible() then return end

    local names = bagItemNames()
    if #names == 0 then
        attempt = (attempt or 0) + 1
        if attempt <= MAX_RETRIES then
            C_Timer.After(RETRY_SECONDS, function() startScan(attempt) end)
        end
        return
    end

    state.queue = names
    state.total = #names
    AP.Bridge.Register(listener, SCAN_EVENTS)
    setSpinnerShown(true)
    if scanButton then scanButton:SetText(CANCEL_LABEL) end
    nextQuery()
end

-- On the selling tab's Full Scan row, right of the AH money frame
function AP.SaleScan.Ensure()
    if scanButton then return true end
    local sellingFrame = AuctionatorSellingFrame
    local moneyFrame = AuctionFrameMoneyFrame
    local fullScanButton = AP.sellingScanButton
    if not sellingFrame or not moneyFrame or not fullScanButton then return false end

    local button = CreateFrame("Button", "AuctionatorPlusSaleScanButton", sellingFrame, "UIPanelButtonTemplate")
    button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    button:SetPoint("LEFT", moneyFrame, "RIGHT", 4, 0)
    button:SetPoint("BOTTOM", fullScanButton, "BOTTOM", 0, 0)
    button:SetText(BUTTON_LABEL)

    button:SetScript("OnClick", function()
        if state.queue then stop() else startScan() end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip_SetTitle(GameTooltip, BUTTON_LABEL)
        GameTooltip_AddHighlightLine(GameTooltip, "Runs one live price search for every item in the bag list, like scanning a shopping list, so the Relative Value and the item glows use current auction prices. Steps aside for your own searches.", true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    sellingFrame:HookScript("OnHide", stop)

    scanButton = button
    return true
end
