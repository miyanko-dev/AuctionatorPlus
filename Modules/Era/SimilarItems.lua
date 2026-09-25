local _, AP = ...

-- Era half of Show Similar Items: once the selling tab's own name search finished, one background category scan on the legacy scanner; auctions matching the sale item join its current-prices listing as extra rows
local Similar = AP.SimilarItems

-- Absorb the burst of StartFakeBuyLoading repeats one placement fires, but re-run on a genuine re-drop
local REDROP_DEBOUNCE = 1.0

local SCAN_EVENTS = { Auctionator.AH.Events.ScanResultsUpdate, Auctionator.AH.Events.ScanAborted }

-- token bumps per placement and supersedes in-flight work; pending is the sale item's profile awaiting comparables; trackedLink and saleKind drive the checkbox
local watch = {
    token = 0,
    lastLink = nil,
    lastProcessAt = nil,
    pending = nil,
    scanning = false,
    scanEntries = nil,
    scanToken = nil,
    trackedLink = nil,
    saleKind = nil,
}
local scanListener, similarCheck, refreshHooked

-- ===== Current-prices listing =====
local function currentPricesFrame()
    local sellingFrame = AuctionatorSellingFrame
    local buyFrame = sellingFrame and sellingFrame.BuyFrame
    return buyFrame and buyFrame.CurrentPrices
end

local function currentPricesProvider()
    local currentPrices = currentPricesFrame()
    return currentPrices and currentPrices.SearchDataProvider
end

-- Auctions the listing takes as its own, mirroring its import: the searched item, and with Auctionator's ignore-suffix option every suffix of it
local function listsNatively(provider, itemLink)
    if AP.Bridge.CleanLink(itemLink) == provider.searchKey then return true end
    return provider.ignoreItemSuffix and C_Item.GetItemInfoInstant(itemLink) == C_Item.GetItemInfoInstant(provider.searchKey)
end

-- A current-prices row the listing would not take as its own is a comparable of ours
local function isComparable(rowData)
    local provider = currentPricesProvider()
    if not (provider and provider.searchKey and rowData and rowData.itemLink) then return false end
    if listsNatively(provider, rowData.itemLink) then return false end
    for _, result in ipairs(provider.currentResults or {}) do
        if result == rowData then return true end
    end
    return false
end

-- Re-run the selling tab's name search; its ViewSetup then re-triggers the comparable scan when a profile is pending
local function refreshCurrentPrices()
    local currentPrices = currentPricesFrame()
    if currentPrices and currentPrices:IsVisible() then
        currentPrices:DoRefresh()
    end
end

-- ===== Sale item tracking =====
-- Bags additionally need their tooltip cached to validate the slot count
local function trackSaleItem(itemLink)
    if itemLink == watch.trackedLink then return end
    watch.trackedLink = itemLink
    watch.saleKind = itemLink and Similar.KindOf(itemLink) or nil
    Similar.ShowCheckbox(watch.saleKind)

    if watch.saleKind ~= "bag" then return end
    local saleItem = Item:CreateFromItemLink(itemLink)
    if not saleItem or saleItem:IsItemEmpty() then return end
    saleItem:ContinueOnItemLoad(function()
        if watch.trackedLink ~= itemLink then return end
        if not AP.ItemStats.ParseSlotCount(AP.ItemStats.Text(itemLink)) then
            watch.saleKind = nil
            Similar.ShowCheckbox(nil)
        end
    end)
end

-- ===== Comparable scan =====
local function stopScan()
    if watch.scanning then
        watch.scanning = false
        AP.Bridge.AbortQuery()
        AP.Bridge.Unregister(scanListener, SCAN_EVENTS)
    end
    watch.scanEntries = nil
end

-- Load every candidate's item data before the callback; levels, stats and slot counts need the item cached
local function ensureLoaded(entries, callback)
    local loading = {}
    for _, entry in ipairs(entries) do
        local entryItem = entry.itemLink and Item:CreateFromItemLink(entry.itemLink)
        if entryItem and not entryItem:IsItemEmpty() and not entryItem:IsItemDataCached() then
            loading[#loading + 1] = entryItem
        end
    end
    local remaining = #loading
    if remaining == 0 then
        callback()
        return
    end
    for _, loadItem in ipairs(loading) do
        loadItem:ContinueOnItemLoad(function()
            remaining = remaining - 1
            if remaining == 0 then callback() end
        end)
    end
end

-- Append the kept auctions to the current-prices listing and repaint
local function mergeIntoProvider(provider, entries)
    if #entries == 0 then return end
    for _, entry in ipairs(entries) do
        entry.page = 0
        entry.query = provider.query
        entry.apComparable = true
        provider.allAuctions[#provider.allAuctions + 1] = entry
    end
    provider:PopulateAuctions()

    -- PopulateAuctions rebuilds every row notReady; ready them again so the merged listing stays hover- and clickable
    for _, result in ipairs(provider.currentResults or {}) do
        result.notReady = false
    end
end

-- Filter the scan against the profile once every candidate's item data is cached, then merge into the current-prices listing
local function injectComparables(pending, entries)
    local provider = currentPricesProvider()
    if not provider or not provider.allAuctions then return end

    -- Never merge into a listing that meanwhile shows a different item
    if AP.Bridge.CleanLink(pending.itemLink) ~= provider.searchKey then return end

    local candidates = {}
    for _, entry in ipairs(entries) do
        local link = entry.itemLink
        if link and not listsNatively(provider, link) and Similar.SameType(pending, link) then
            candidates[#candidates + 1] = entry
        end
    end

    ensureLoaded(candidates, function()
        if watch.pending ~= pending then return end
        local matches = {}
        for _, entry in ipairs(candidates) do
            if Similar.Matches(pending, entry.itemLink) then
                matches[#matches + 1] = entry
            end
        end
        mergeIntoProvider(provider, matches)
    end)
end

-- Scan the profile's category in the background; safe on the shared scanner because the selling tab's own name search has just finished
local function runComparableSearch(pending)
    watch.scanEntries = {}
    watch.scanning = true
    watch.scanToken = pending.token
    AP.Bridge.Register(scanListener, SCAN_EVENTS)

    local minLevel, maxLevel = Similar.LevelRange(pending)
    local started = AP.Bridge.Query({
        searchString = "",
        minLevel = minLevel,
        maxLevel = maxLevel,
        itemClassFilters = pending.filters,
        isExact = false,
    })

    -- A failed start means the scanner belongs to another component; clean up without aborting their scan
    if not started then
        watch.scanning = false
        AP.Bridge.Unregister(scanListener, SCAN_EVENTS)
        watch.scanEntries = nil
    end
end

-- Auctionator reuses allAuctions across placements, so merged rows must never survive into the next item's listing
local function removeMergedComparables()
    local provider = currentPricesProvider()
    if not provider or not provider.allAuctions then return end
    for index = #provider.allAuctions, 1, -1 do
        if provider.allAuctions[index].apComparable then
            table.remove(provider.allAuctions, index)
        end
    end
end

-- Drop the captured profile and any scan built on it; a bumped token also cancels deferred item-load work
local function invalidatePending()
    watch.token = watch.token + 1
    watch.pending = nil
    stopScan()
    removeMergedComparables()
end

local function commitPending(itemLink)
    watch.lastLink = itemLink
    watch.lastProcessAt = GetTime()

    local profile = Similar.ProfileFor(itemLink)
    if not profile then
        watch.pending = nil
        return
    end
    profile.token = watch.token
    watch.pending = profile
end

-- Capture the profile now; the comparable scan starts on ViewSetup so it never fights the selling tab's own name search for the scanner
local function startForItem(itemLink)
    invalidatePending()

    if C_Item.GetItemInfo(itemLink) then
        commitPending(itemLink)
        return
    end
    local token = watch.token
    local pendingItem = Item:CreateFromItemLink(itemLink)
    if pendingItem and not pendingItem:IsItemEmpty() then
        pendingItem:ContinueOnItemLoad(function()
            if token == watch.token then commitPending(itemLink) end
        end)
    end
end

-- Auctionator can focus a comparable on its own, re-selecting the first row after a post; once its undercut handler ran, hand over the row's exact unit price instead
local function takeOverPrice(rowData)
    local pending = watch.pending
    local provider = currentPricesProvider()
    if not rowData or not rowData.unitPrice or not pending or not provider then return end
    if AP.Bridge.CleanLink(pending.itemLink) ~= provider.searchKey or not isComparable(rowData) then return end

    C_Timer.After(0, function()
        if rowData.isSelected then AP.Bridge.SelectPrice(rowData.unitPrice) end
    end)
end

local function collectResults(results, gotAllResults)
    if not watch.scanning then return end
    if type(results) == "table" then
        for _, entry in ipairs(results) do
            watch.scanEntries[#watch.scanEntries + 1] = entry
        end
    end
    if not gotAllResults then return end

    local pending, collected, token = watch.pending, watch.scanEntries, watch.scanToken
    watch.scanning = false
    AP.Bridge.Unregister(scanListener, SCAN_EVENTS)
    watch.scanEntries = nil
    if pending and pending.token == token then
        injectComparables(pending, collected)
    end
end

local function onSaleItem(itemLink)
    if not itemLink then return end

    -- A different item entered the sale slot; the old profile must never scan under the new listing
    if itemLink ~= watch.trackedLink then invalidatePending() end
    trackSaleItem(itemLink)
    if not Similar.IsWanted(watch.saleKind) then return end

    -- Skip the rapid repeat fires for the item just handled; a later re-drop still re-runs
    if itemLink == watch.lastLink and watch.lastProcessAt and (GetTime() - watch.lastProcessAt) < REDROP_DEBOUNCE then
        return
    end
    startForItem(itemLink)
end

-- The selling tab's name search finished, so the scanner is free for ours
local function onViewSetup()
    local pending = watch.pending
    if not pending or pending.searchStarted then return end
    pending.searchStarted = true
    C_Timer.After(0, function()
        if watch.pending == pending then runComparableSearch(pending) end
    end)
end

local function receiveEvent(_, eventName, eventData, gotAllResults)
    if eventName == Auctionator.Selling.Events.StartFakeBuyLoading then
        onSaleItem(eventData and eventData.itemLink)
    elseif eventName == Auctionator.Selling.Events.ClearBagItem then
        invalidatePending()
        watch.lastLink = nil
        trackSaleItem(nil)
    elseif eventName == Auctionator.Buying.Events.AuctionFocussed then
        takeOverPrice(eventData)
    elseif eventName == Auctionator.Buying.Events.ViewSetup then
        onViewSetup()
    elseif eventName == Auctionator.AH.Events.ScanResultsUpdate then
        collectResults(eventData, gotAllResults)
    elseif eventName == Auctionator.AH.Events.ScanAborted and watch.scanning then
        watch.scanning = false
        AP.Bridge.Unregister(scanListener, SCAN_EVENTS)
        watch.scanEntries = nil
    end
end

scanListener = AP.Bridge.Listen({
    Auctionator.Selling.Events.StartFakeBuyLoading,
    Auctionator.Selling.Events.ClearBagItem,
    Auctionator.Buying.Events.ViewSetup,
    Auctionator.Buying.Events.AuctionFocussed,
}, receiveEvent)

-- ===== Row hooks, replaced on the mixin before the AH creates any rows =====
-- A comparable must never reach Auctionator's own row click, which selects it for Buy or Cancel on any mouse button: modified clicks link or preview the item, a left click hands over its exact unit price
local baseRowClick = AuctionatorBuyAuctionsResultsRowMixin.OnClick
function AuctionatorBuyAuctionsResultsRowMixin:OnClick(button, ...)
    local row = self.rowData
    if not isComparable(row) then
        return baseRowClick(self, button, ...)
    end
    if IsModifiedClick("CHATLINK") or IsModifiedClick("DRESSUP") then
        HandleModifiedItemClick(row.itemLink)
    elseif button == "LeftButton" and row.unitPrice then
        AP.Bridge.SelectPrice(row.unitPrice)
    end
end

-- The stock row tooltip only previews equipment; extend it to every linked row so bags and other comparables preview too
local baseRowEnter = AuctionatorBuyAuctionsResultsRowMixin.OnEnter
function AuctionatorBuyAuctionsResultsRowMixin:OnEnter()
    baseRowEnter(self)
    local link = self.rowData and self.rowData.itemLink
    if not link or AP.Bridge.IsEquipment(select(6, C_Item.GetItemInfoInstant(link))) then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
end

-- ===== Host frames =====
-- Above the bag panel, where Auctionator's legacy selling layout leaves room
local function ensureCheckbox()
    if similarCheck then return true end
    local sellingFrame = AuctionatorSellingFrame
    local inset = sellingFrame and sellingFrame.BagInset
    if not inset then return false end

    similarCheck = Similar.CreateCheckbox(sellingFrame, function(checked)
        -- Apply the new state to the slotted item right away; the refresh rebuilds the listing with or without comparables
        if checked and watch.trackedLink then
            startForItem(watch.trackedLink)
        else
            invalidatePending()
        end
        refreshCurrentPrices()
    end)
    similarCheck:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", 4, 3)
    return true
end

-- Refresh re-runs the name search, so the next ViewSetup has to start the comparable scan again
local function hookRefreshButton()
    if refreshHooked then return true end
    local currentPrices = currentPricesFrame()
    local refreshButton = currentPrices and currentPrices.RefreshButton
    if not refreshButton then return false end

    refreshButton:HookScript("OnClick", function()
        if not watch.pending then return end
        stopScan()
        watch.pending.searchStarted = false
    end)
    refreshHooked = true
    return true
end

function AP.SimilarItems.Ensure()
    local checkboxReady = ensureCheckbox()
    local refreshReady = hookRefreshButton()
    return checkboxReady and refreshReady
end
