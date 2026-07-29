local _, AP = ...

AP.SellingWatch = {}

-- Ignore non-gear equip locations; trade goods and unequippable items report an empty equipLoc.
local NON_GEAR_SLOTS = {
    [""] = true,
    INVTYPE_BAG = true,
    INVTYPE_QUIVER = true,
    INVTYPE_AMMO = true,
    INVTYPE_NON_EQUIP = true,
    INVTYPE_NON_EQUIP_IGNORE = true,
}

-- Body-armor slots carry an armor-type distinction; cloak, neck, finger and trinket are wearable by all classes, so they are excluded.
local BODY_ARMOR_SLOTS = {
    INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true,
    INVTYPE_ROBE = true, INVTYPE_WAIST = true, INVTYPE_LEGS = true,
    INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
}

local ITEM_LEVEL_RANGE = 2

-- Absorb the burst of StartFakeBuyLoading repeats one placement fires, but re-run on a genuine re-drop.
local REDROP_DEBOUNCE = 1.0

local watch = {
    token = 0,          -- bumped per placement; supersedes in-flight work
    lastLink = nil,
    lastProcessAt = nil,
    pending = nil,      -- profile of the current sale item awaiting comparables
    scanning = false,
    scanEntries = nil,
    scanToken = nil,
    trackedLink = nil,  -- sale-slot item driving the checkbox state
    saleKind = nil,     -- "gear" | "bag" | nil; drives checkbox visibility and label
}
local scanListener

local CHECKBOX_TEXT = {
    gear = {
        label = "Show Similar Items",
        tooltip = "When a piece of gear is placed for sale, also list auctions of the same slot and armor type within 2 item levels that carry the same stats as the item being sold. Stat values are ignored. Click a similar auction to take its unit price for your listing.",
    },
    bag = {
        label = "Show Similar Bags",
        tooltip = "When a container is placed for sale, also list auctions of all containers with the same number of slots. Click a similar auction to take its unit price for your listing.",
    },
}

local function isSupportedGear(equipLoc)
    return type(equipLoc) == "string" and NON_GEAR_SLOTS[equipLoc] ~= true
end

-- Sale-item kind from instant info; containers and quivers count as bags, everything equippable as gear.
local function saleKindFor(itemLink)
    local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(itemLink)
    if classID == Enum.ItemClass.Container or classID == Enum.ItemClass.Quiver then
        return "bag"
    end
    if isSupportedGear(equipLoc) then
        return "gear"
    end
    return nil
end

local function checkboxSetting()
    if watch.saleKind == "bag" then return AP.Settings.showSimilarBags end
    return AP.Settings.showSimilarItems
end

-- The checkbox only exists for gear and containers; label and persisted setting follow the sale item's kind.
local function updateCheckbox()
    local check = AP.showSimilarButton
    if not check then return end

    local text = CHECKBOX_TEXT[watch.saleKind]
    if not text then
        check:Hide()
        return
    end
    check.apLabel:SetText(text.label)
    check:SetChecked(checkboxSetting())
    check:Show()
end

-- Track what sits in the sale slot; bags additionally need their tooltip cached to validate the slot count.
local function trackSaleItem(itemLink)
    if itemLink == watch.trackedLink then return end
    watch.trackedLink = itemLink
    watch.saleKind = itemLink and saleKindFor(itemLink) or nil
    updateCheckbox()

    if watch.saleKind ~= "bag" then return end
    local saleItem = Item:CreateFromItemLink(itemLink)
    if not saleItem or saleItem:IsItemEmpty() then return end
    saleItem:ContinueOnItemLoad(function()
        if watch.trackedLink ~= itemLink then return end
        if not AP.StatScan.ParseSlotCount(AP.StatScan.ReadItemText(itemLink)) then
            watch.saleKind = nil
            updateCheckbox()
        end
    end)
end

-- Compare weapons by weapon type only (restricted server-side via the category); narrow armor by slot, plus armor type for body slots.
local function buildFilter(classID, equipLoc, itemSubType)
    local filter = {}
    if classID ~= Enum.ItemClass.Weapon then
        filter.equipLoc = equipLoc
        if BODY_ARMOR_SLOTS[equipLoc] then
            filter.armorSubType = itemSubType
        end
    end
    return filter
end

-- classID + Auctionator categoryKey, slot-scoped where the category tree has the slot ("Armor/Mail/Hands"), otherwise class/subclass ("Weapon/Daggers").
local function categoryForItem(itemLink, equipLoc)
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemLink)
    if not classID then return nil end
    local className = C_Item.GetItemClassInfo(classID)
    if not className then return nil end

    local subName = subClassID and C_Item.GetItemSubClassInfo(classID, subClassID)
    local categoryKey = className
    if subName and subName ~= "" then
        categoryKey = categoryKey .. "/" .. subName
    end
    local slotName = equipLoc and _G[equipLoc]
    if slotName and slotName ~= "" then
        local withSlot = categoryKey .. "/" .. slotName
        if Auctionator.Search.GetItemClassCategories(withSlot) then
            categoryKey = withSlot
        end
    end
    return classID, categoryKey
end

-- Build the comparison profile for the dropped sale item, synchronous since the slotted item is cached; nil for unsupported items.
local function profileForItem(itemLink)
    local kind = saleKindFor(itemLink)

    if kind == "bag" then
        local slotCount = AP.StatScan.ParseSlotCount(AP.StatScan.ReadItemText(itemLink))
        if not slotCount then return nil end
        local classID = select(6, C_Item.GetItemInfoInstant(itemLink))
        local className = classID and C_Item.GetItemClassInfo(classID)
        if not className then return nil end
        -- The bare class key ("Container") spans every bag subtype, so soul and profession bags compare too.
        return {
            kind = kind,
            itemLink = itemLink,
            categoryKey = className,
            slotCount = slotCount,
        }
    end

    if kind ~= "gear" then return nil end
    local equipLoc, _, itemSubType = AP.StatScan.GetEquipInfo(itemLink)
    if not equipLoc then return nil end
    local classID, categoryKey = categoryForItem(itemLink, equipLoc)
    if not categoryKey then return nil end

    local filter = buildFilter(classID, equipLoc, itemSubType)
    local itemLevel = select(4, C_Item.GetItemInfo(itemLink)) or 0
    if itemLevel > 0 then
        filter.minItemLevel = itemLevel - ITEM_LEVEL_RANGE
        filter.maxItemLevel = itemLevel + ITEM_LEVEL_RANGE
    end

    return {
        kind = kind,
        itemLink = itemLink,
        categoryKey = categoryKey,
        filter = filter,
        statSet = AP.StatScan.PrimaryStatSet(AP.StatScan.ReadItemText(itemLink)),
    }
end

-- Gear must sit in the same slot/armor type, within the item-level window, and carry the same primary-stat set; bags must hold the same number of slots.
local function matchesProfile(pending, itemLink)
    local itemText = AP.StatScan.ReadItemText(itemLink)

    if pending.kind == "bag" then
        return AP.StatScan.ParseSlotCount(itemText) == pending.slotCount
    end

    local filter = pending.filter
    local equipLoc, _, subType = AP.StatScan.GetEquipInfo(itemLink)
    if filter.equipLoc and equipLoc ~= filter.equipLoc then return false end
    if filter.armorSubType and subType ~= filter.armorSubType then return false end
    if filter.minItemLevel then
        local itemLevel = select(4, C_Item.GetItemInfo(itemLink))
        if not itemLevel or itemLevel < filter.minItemLevel or itemLevel > filter.maxItemLevel then
            return false
        end
    end
    return AP.StatScan.SameStatSet(AP.StatScan.PrimaryStatSet(itemText), pending.statSet)
end

-- The selling tab's live current-prices frame (name-based listing).
local function currentPricesFrame()
    local frame = _G.AuctionatorSellingFrame
    local buyFrame = frame and frame.BuyFrame
    return buyFrame and buyFrame.CurrentPrices
end

local function currentPricesProvider()
    local currentPrices = currentPricesFrame()
    return currentPrices and currentPrices.SearchDataProvider
end

-- Re-run the selling tab's name search; its ViewSetup then re-triggers the comparable scan when a profile is pending.
local function refreshCurrentPrices()
    local currentPrices = currentPricesFrame()
    if currentPrices and currentPrices:IsVisible() then
        currentPrices:DoRefresh()
    end
end

local function scanEvents()
    return { Auctionator.AH.Events.ScanResultsUpdate, Auctionator.AH.Events.ScanAborted }
end

local function stopScan()
    if watch.scanning then
        watch.scanning = false
        Auctionator.AH.AbortQuery()
        Auctionator.EventBus:Unregister(scanListener, scanEvents())
    end
    watch.scanEntries = nil
end

-- Load every candidate's item data before the callback; item level, stats and slot counts need the item cached.
local function ensureLoaded(entries, callback)
    local loading = {}
    for _, entry in ipairs(entries) do
        local entryItem = entry.itemLink and Item:CreateFromItemLink(entry.itemLink)
        if entryItem and not entryItem:IsItemEmpty() and not entryItem:IsItemDataCached() then
            table.insert(loading, entryItem)
        end
    end
    local remaining = #loading
    if remaining == 0 then callback(); return end
    for _, loadItem in ipairs(loading) do
        loadItem:ContinueOnItemLoad(function()
            remaining = remaining - 1
            if remaining == 0 then callback() end
        end)
    end
end

-- Append the kept entries to the current-prices listing and repaint.
local function mergeIntoProvider(provider, entries)
    local added = 0
    for _, entry in ipairs(entries) do
        entry.page = 0
        entry.query = provider.query
        entry.apComparable = true
        table.insert(provider.allAuctions, entry)
        added = added + 1
    end
    if added == 0 then return end
    provider:PopulateAuctions()
    -- PopulateAuctions rebuilds every row notReady; ready them again so the merged listing stays hover- and clickable.
    for _, result in ipairs(provider.currentResults or {}) do
        result.notReady = false
    end
end

-- Filter the scan against the profile once every candidate's item data is cached, then merge into the current-prices listing.
local function injectComparables(pending, entries)
    local provider = currentPricesProvider()
    if not provider or not provider.allAuctions then return end
    -- Never merge into a listing that meanwhile shows a different item.
    if Auctionator.Search.GetCleanItemLink(pending.itemLink) ~= provider.searchKey then return end

    local candidates = {}
    for _, entry in ipairs(entries) do
        local link = entry.itemLink
        if link and Auctionator.Search.GetCleanItemLink(link) ~= provider.searchKey then
            table.insert(candidates, entry)
        end
    end

    ensureLoaded(candidates, function()
        if watch.pending ~= pending then return end
        local matches = {}
        for _, entry in ipairs(candidates) do
            if matchesProfile(pending, entry.itemLink) then
                table.insert(matches, entry)
            end
        end
        mergeIntoProvider(provider, matches)
    end)
end

-- Scan the profile's category in the background; safe on the shared scanner because the selling tab's own name search has just finished.
local function runComparableSearch(pending)
    watch.scanEntries = {}
    watch.scanning = true
    watch.scanToken = pending.token
    Auctionator.EventBus:Register(scanListener, scanEvents())

    local ok = pcall(Auctionator.AH.QueryAuctionItems, {
        searchString = "",
        itemClassFilters = Auctionator.Search.GetItemClassCategories(pending.categoryKey) or {},
        isExact = false,
    })
    -- A failed start means the scanner belongs to another component; clean up without aborting their scan.
    if not ok then
        watch.scanning = false
        Auctionator.EventBus:Unregister(scanListener, scanEvents())
        watch.scanEntries = nil
    end
end

-- Native code reuses allAuctions across placements, so merged rows must never survive into the next item's listing.
local function removeMergedComparables()
    local provider = currentPricesProvider()
    if not provider or not provider.allAuctions then return end
    for index = #provider.allAuctions, 1, -1 do
        if provider.allAuctions[index].apComparable then
            table.remove(provider.allAuctions, index)
        end
    end
end

-- Drop the captured profile and any scan built on it; a bumped token also cancels deferred item-load work.
local function invalidatePending()
    watch.token = watch.token + 1
    watch.pending = nil
    stopScan()
    removeMergedComparables()
end

local function commitPending(itemLink)
    watch.lastLink = itemLink
    watch.lastProcessAt = GetTime()

    local profile = profileForItem(itemLink)
    if not profile then
        watch.pending = nil
        return
    end
    profile.token = watch.token
    watch.pending = profile
end

-- Capture the profile now; the comparable search starts on ViewSetup so it never fights the selling tab's own name search for the scanner.
local function startForItem(itemLink)
    invalidatePending()

    if C_Item.GetItemInfo(itemLink) then
        commitPending(itemLink)
    else
        local token = watch.token
        local pendingItem = Item:CreateFromItemLink(itemLink)
        if pendingItem and not pendingItem:IsItemEmpty() then
            pendingItem:ContinueOnItemLoad(function()
                if token == watch.token then commitPending(itemLink) end
            end)
        end
    end
end

-- A focussed current-prices row that isn't the sale item is a comparable of ours; once Auctionator's own undercut handler ran, take the row's exact unit price instead.
local function takeOverPrice(rowData)
    if not rowData or not rowData.unitPrice or not watch.trackedLink then return end
    local provider = currentPricesProvider()
    if not provider or not provider.currentResults or not provider.searchKey then return end
    -- Comparables exist only while a profile for the currently searched item is live; anything else is a stale row.
    if not watch.pending
        or Auctionator.Search.GetCleanItemLink(watch.pending.itemLink) ~= provider.searchKey then
        return
    end
    if Auctionator.Search.GetCleanItemLink(rowData.itemLink) == provider.searchKey then return end

    local isComparable = false
    for _, result in ipairs(provider.currentResults) do
        if result == rowData then
            isComparable = true
            break
        end
    end
    if not isComparable then return end

    C_Timer.After(0, function()
        local sellingFrame = _G.AuctionatorSellingFrame
        local saleItem = sellingFrame and sellingFrame.SaleItemFrame
        if saleItem and saleItem.itemInfo and rowData.isSelected then
            saleItem:SetUnitPrice(rowData.unitPrice)
        end
    end)
end

local function receiveEvent(_, eventName, eventData, arg3)
    local sellingEvents = Auctionator.Selling.Events
    local buyingEvents = Auctionator.Buying.Events
    local AH = Auctionator.AH.Events

    if eventName == sellingEvents.StartFakeBuyLoading then
        local link = eventData and eventData.itemLink
        if not link then return end
        -- A different item entered the sale slot; the old profile must never scan under the new listing.
        if link ~= watch.trackedLink then invalidatePending() end
        trackSaleItem(link)
        if not watch.saleKind or not checkboxSetting() then return end
        -- Skip the rapid repeat fires for the item just handled; a later re-drop still re-runs.
        if link == watch.lastLink and watch.lastProcessAt
            and (GetTime() - watch.lastProcessAt) < REDROP_DEBOUNCE then
            return
        end
        startForItem(link)

    elseif eventName == sellingEvents.ClearBagItem then
        invalidatePending()
        watch.lastLink = nil
        trackSaleItem(nil)

    elseif eventName == buyingEvents.AuctionFocussed then
        takeOverPrice(eventData)

    elseif eventName == buyingEvents.ViewSetup then
        -- The selling tab's name search finished; the scanner is free for ours.
        local pending = watch.pending
        if pending and not pending.searchStarted then
            pending.searchStarted = true
            C_Timer.After(0, function()
                if watch.pending == pending then runComparableSearch(pending) end
            end)
        end

    elseif eventName == AH.ScanResultsUpdate then
        if not watch.scanning then return end
        if type(eventData) == "table" then
            for _, entry in ipairs(eventData) do
                table.insert(watch.scanEntries, entry)
            end
        end
        if arg3 then -- gotAllResults
            local pending, collected, token = watch.pending, watch.scanEntries, watch.scanToken
            watch.scanning = false
            Auctionator.EventBus:Unregister(scanListener, scanEvents())
            watch.scanEntries = nil
            if pending and pending.token == token then
                injectComparables(pending, collected)
            end
        end

    elseif eventName == AH.ScanAborted then
        if watch.scanning then
            watch.scanning = false
            Auctionator.EventBus:Unregister(scanListener, scanEvents())
            watch.scanEntries = nil
        end
    end
end

scanListener = AP.Bridge.Listen({
    Auctionator.Selling.Events.StartFakeBuyLoading,
    Auctionator.Selling.Events.ClearBagItem,
    Auctionator.Buying.Events.ViewSetup,
    Auctionator.Buying.Events.AuctionFocussed,
}, receiveEvent)

-- The stock row tooltip only previews equipment; extend it to every linked row so bags and other comparables preview too. Wrapped before the AH UI creates any rows.
local baseRowEnter = AuctionatorBuyAuctionsResultsRowMixin
    and AuctionatorBuyAuctionsResultsRowMixin.OnEnter
if baseRowEnter then
    function AuctionatorBuyAuctionsResultsRowMixin:OnEnter()
        baseRowEnter(self)
        local link = self.rowData and self.rowData.itemLink
        if not link
            or Auctionator.Utilities.IsEquipment(select(6, C_Item.GetItemInfoInstant(link))) then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end
end

local function ensureCheckbox()
    if AP.showSimilarButton then return true end
    local sellingFrame = _G.AuctionatorSellingFrame
    local anchor = sellingFrame and (sellingFrame.BagInset or sellingFrame)
    if not sellingFrame or not anchor then return false end

    local check = CreateFrame(
        "CheckButton", "AuctionatorPlusShowSimilar", sellingFrame, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 4, 3)

    local label = check:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check.apLabel = label

    check:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        if watch.saleKind == "bag" then
            AP.Settings.showSimilarBags = checked
        else
            AP.Settings.showSimilarItems = checked
        end
        AP.SaveSettings()

        -- Apply the new state to the slotted item right away; the refresh rebuilds the listing with or without comparables.
        if checked and watch.trackedLink then
            startForItem(watch.trackedLink)
        else
            invalidatePending()
        end
        refreshCurrentPrices()
    end)
    check:SetScript("OnEnter", function(self)
        local text = CHECKBOX_TEXT[watch.saleKind]
        if not text then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text.label)
        GameTooltip:AddLine(text.tooltip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", GameTooltip_Hide)

    AP.showSimilarButton = check
    updateCheckbox()

    return true
end

local function hookRefreshButton()
    if AP.refreshButtonHooked then return true end
    local currentPrices = currentPricesFrame()
    local refreshButton = currentPrices and currentPrices.RefreshButton
    if not refreshButton then return false end

    -- Clear searchStarted so the next ViewSetup re-triggers the comparable scan after Refresh re-runs the name search.
    refreshButton:HookScript("OnClick", function()
        if not watch.pending then return end
        stopScan()
        watch.pending.searchStarted = false
    end)

    AP.refreshButtonHooked = true
    return true
end

function AP.SellingWatch.Ensure()
    local checkboxOk = ensureCheckbox()
    local refreshOk = hookRefreshButton()
    return checkboxOk and refreshOk
end
