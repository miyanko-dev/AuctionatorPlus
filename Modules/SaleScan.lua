local _, AP = ...

-- "Sale Scan": a button right of the AH money frame in the selling tab. One click runs a live exact-name search per distinct bag-listing item — the same sequential term scan a shopping list runs, first page only since only the lowest price matters — feeding Auctionator's price database so Rel. Value and the bag glow reflect current prices.
AP.SaleScan = {}

local BUTTON_LABEL = "Sale Scan"
local CANCEL_LABEL = "Cancel Scan"
local BUTTON_WIDTH = 110
local BUTTON_HEIGHT = 22
local RETRY_SECONDS = 0.5  -- the bag view fills asynchronously after the tab opens
local MAX_RETRIES = 6

local SCAN_LIST_NAME = "Bags"  -- shown as the list name in the shared search-progress locale string

local state = {
    queue = nil,      -- item names still to scan; nil while idle
    total = 0,
    entries = nil,    -- results collected for the in-flight query
    scanning = false,
    aborting = false, -- we cut the query short ourselves; expect ScanAborted
}
local listener

local function scanEvents()
    return {
        Auctionator.AH.Events.ScanResultsUpdate,
        Auctionator.AH.Events.ScanAborted,
        Auctionator.AH.Events.ThrottleUpdate,
        Auctionator.Selling.Events.StartFakeBuyLoading,
    }
end

local function spinnerListing()
    local buyFrame = _G.AuctionatorSellingFrame and _G.AuctionatorSellingFrame.BuyFrame
    local currentPrices = buyFrame and buyFrame.CurrentPrices
    return currentPrices and currentPrices.SearchResultsListing
end

-- Same progress line a shopping list scan shows ("Search for item X/Y in ..."), via Auctionator's own locale string.
local function setProgressText()
    local listing = spinnerListing()
    local resultsText = listing and listing.ScrollArea and listing.ScrollArea.ResultsText
    if not resultsText then return end
    resultsText:SetText(Auctionator.Locales.Apply(
        "LIST_SEARCH_STATUS", state.total - #state.queue, state.total, SCAN_LIST_NAME))
end

-- The current-prices listing carries the same spinner the shopping results use; borrow it for scan progress. An empty panel's "No results" would sit under the spinner, so stash it away and put it back on stop; the progress text swap is restored too, since the listing reuses it for its own searches.
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
    else
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
end

local function stop()
    if not state.queue then return end
    Auctionator.EventBus:Unregister(listener, scanEvents())
    state.queue = nil
    state.entries = nil
    state.scanning = false
    state.aborting = false
    setSpinnerShown(false)
    if AP.saleScanButton then
        AP.saleScanButton:SetText(BUTTON_LABEL)
    end
end

-- One query at a time: the legacy scanner has no queue and StartQuery stomps whatever runs.
local function nextQuery()
    if not state.queue or state.scanning then return end
    if not Auctionator.AH.IsNotThrottled() then return end

    local itemName = table.remove(state.queue, 1)
    if not itemName then
        stop()
        return
    end

    setProgressText()
    state.entries = {}
    state.scanning = true
    local ok = pcall(Auctionator.AH.QueryAuctionItems, {
        searchString = itemName,
        isExact = true,
    })
    if not ok then stop() end
end

local function finishQuery()
    local batch = state.entries
    state.entries = nil
    state.scanning = false
    if #batch > 0 then
        Auctionator.Search.GroupResultsForDB(batch)
    end
    AP.BagGlow.Repaint()
    nextQuery()
end

local function receiveEvent(_, eventName, eventData, gotAllResults)
    local AH = Auctionator.AH.Events

    if eventName == AH.ScanResultsUpdate then
        if not state.scanning then return end
        if type(eventData) == "table" then
            for _, entry in ipairs(eventData) do
                state.entries[#state.entries + 1] = entry
            end
        end
        if gotAllResults then
            finishQuery()
        else
            -- pages arrive sorted by unit price, so the first already holds the cheapest; skip the rest like a shopping search without "always load more"
            state.aborting = true
            Auctionator.AH.AbortQuery()
        end

    elseif eventName == AH.ScanAborted then
        if state.aborting then
            state.aborting = false
            finishQuery()
        elseif state.scanning then
            -- another search stomped ours; whatever the user started wins
            stop()
        end

    elseif eventName == AH.ThrottleUpdate then
        if eventData == true then nextQuery() end

    elseif eventName == Auctionator.Selling.Events.StartFakeBuyLoading then
        -- an item entered the sale slot; leave the scanner to the selling flow
        stop()
    end
end

listener = { receiveEvent = receiveEvent }

local function bagItemNames()
    local listing = _G.AuctionatorSellingFrame and _G.AuctionatorSellingFrame.BagListing
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
    local sellingFrame = _G.AuctionatorSellingFrame
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
    Auctionator.EventBus:Register(listener, scanEvents())
    setSpinnerShown(true)
    if AP.saleScanButton then
        AP.saleScanButton:SetText(CANCEL_LABEL)
    end
    nextQuery()
end

function AP.SaleScan.Ensure()
    if AP.saleScanButton then return true end
    local sellingFrame = _G.AuctionatorSellingFrame
    local moneyFrame = _G.AuctionFrameMoneyFrame
    local fullScanButton = AP.fullScanSellingButton
    if not sellingFrame or not moneyFrame or not fullScanButton then return false end

    local button = CreateFrame(
        "Button", "AuctionatorPlusSaleScanButton", sellingFrame, "UIPanelButtonTemplate")
    button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)

    -- Same bottom line as the selling tab's Full Scan button (created first in Bootstrap's chain).
    button:SetPoint("LEFT", moneyFrame, "RIGHT", 4, 0)
    button:SetPoint("BOTTOM", fullScanButton, "BOTTOM", 0, 0)
    button:SetText(BUTTON_LABEL)

    button:SetScript("OnClick", function()
        if state.queue then stop() else startScan() end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(BUTTON_LABEL)
        GameTooltip:AddLine(
            "Runs one live price search for every item in the bag list, like scanning a shopping list, so Rel. Value and the item glows use current auction prices. Steps aside for your own searches.",
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    sellingFrame:HookScript("OnHide", stop)

    AP.saleScanButton = button
    return true
end
