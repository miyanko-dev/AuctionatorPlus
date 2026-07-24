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

local LEVEL_RANGE = 2

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
    saleIsGear = false,
}
local scanListener

local function isSupportedGear(equipLoc)
    return type(equipLoc) == "string" and NON_GEAR_SLOTS[equipLoc] ~= true
end

-- Grey the pair out without supported gear in the sale slot; Same Stats additionally requires Check Similar Items on, and weapons count since their stat matching compares DPS presence.
local function updateCheckboxState()
    local check, sameStats = AP.checkOtherItemsButton, AP.sameStatsButton
    if not check then return end

    if watch.saleIsGear then
        check:Enable()
        check.apLabel:SetFontObject("GameFontNormalSmall")
    else
        check:Disable()
        check.apLabel:SetFontObject("GameFontDisableSmall")
    end

    if watch.saleIsGear and AP.Settings.checkOtherItems then
        sameStats:Enable()
        sameStats.apLabel:SetFontObject("GameFontNormalSmall")
    else
        sameStats:Disable()
        sameStats.apLabel:SetFontObject("GameFontDisableSmall")
    end
end

-- Track what sits in the sale slot; the equip location is only readable once cached, so the state settles in the load callback.
local function trackSaleItem(itemLink)
    if itemLink == watch.trackedLink then return end
    watch.trackedLink = itemLink
    watch.saleIsGear = false
    updateCheckboxState()

    local saleItem = itemLink and Item:CreateFromItemLink(itemLink)
    if not saleItem or saleItem:IsItemEmpty() then return end
    saleItem:ContinueOnItemLoad(function()
        if watch.trackedLink ~= itemLink then return end
        local equipLoc = AP.StatScan.GetEquipInfo(itemLink)
        watch.saleIsGear = isSupportedGear(equipLoc)
        updateCheckboxState()
    end)
end

-- Compare weapons by weapon type only (restricted server-side via the category); narrow armor by slot, plus armor type for body slots.
local function buildFilter(classID, equipLoc, itemSubType)
    if classID == Enum.ItemClass.Weapon then
        return nil
    end
    local filter = { equipLoc = equipLoc }
    if BODY_ARMOR_SLOTS[equipLoc] then
        filter.armorSubType = itemSubType
    end
    return filter
end

-- classID + Auctionator categoryKey, slot-scoped for body armor ("Armor/Mail/Hands"), otherwise class/subclass ("Weapon/Daggers").
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
    if BODY_ARMOR_SLOTS[equipLoc] then
        local slotName = _G[equipLoc]
        if slotName and slotName ~= "" then
            local withSlot = categoryKey .. "/" .. slotName
            if Auctionator.Search.GetItemClassCategories(withSlot) then
                categoryKey = withSlot
            end
        end
    end
    return classID, categoryKey
end

-- Build the comparison profile for the dropped sale item, synchronous since the slotted item is cached; nil for unsupported items.
local function profileForItem(itemLink)
    local equipLoc, _, itemSubType = AP.StatScan.GetEquipInfo(itemLink)
    if not isSupportedGear(equipLoc) then return nil end

    local classID, categoryKey = categoryForItem(itemLink, equipLoc)
    if not categoryKey then return nil end

    local requiredLevel = select(5, C_Item.GetItemInfo(itemLink)) or 0
    local minLevel, maxLevel
    if requiredLevel > 0 then
        minLevel = math.max(1, requiredLevel - LEVEL_RANGE)
        maxLevel = requiredLevel + LEVEL_RANGE
    end

    return {
        itemLink = itemLink,
        categoryKey = categoryKey,
        filter = buildFilter(classID, equipLoc, itemSubType),
        minLevel = minLevel,
        maxLevel = maxLevel,
        statSet = AP.StatScan.PrimaryStatSet(AP.StatScan.ReadItemText(itemLink)),
    }
end

-- Candidate must sit in the same slot/armor type as the dropped item.
local function passesFilter(itemLink, filter)
    if not filter then return true end
    local equipLoc, _, subType = AP.StatScan.GetEquipInfo(itemLink)
    if not equipLoc then return false end
    if filter.equipLoc and equipLoc ~= filter.equipLoc then return false end
    if filter.armorSubType and subType ~= filter.armorSubType then return false end
    return true
end

-- The selling tab's live current-prices data provider (name-based listing).
local function currentPricesProvider()
    local frame = _G.AuctionatorSellingFrame
    local buyFrame = frame and frame.BuyFrame
    local currentPrices = buyFrame and buyFrame.CurrentPrices
    return currentPrices and currentPrices.SearchDataProvider
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

-- Load every candidate's item data before the callback; stat tooltips on random-suffix gear need the item cached.
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
        table.insert(provider.allAuctions, entry)
        added = added + 1
    end
    if added > 0 then provider:PopulateAuctions() end
end

-- Merge slot/armor/level matches into the current-prices listing; with "Same Stats" on, narrow to the exact primary-stat set of the dropped item (values ignored).
local function injectComparables(pending, entries)
    local provider = currentPricesProvider()
    if not provider or not provider.allAuctions then return end

    local candidates = {}
    for _, entry in ipairs(entries) do
        local link = entry.itemLink
        if link
            and Auctionator.Search.GetCleanItemLink(link) ~= provider.searchKey
            and passesFilter(link, pending.filter) then
            table.insert(candidates, entry)
        end
    end

    if not (AP.Settings.sameStats and pending.statSet) then
        mergeIntoProvider(provider, candidates)
        return
    end

    ensureLoaded(candidates, function()
        if watch.pending ~= pending then return end
        local matches = {}
        for _, entry in ipairs(candidates) do
            local set = AP.StatScan.PrimaryStatSet(AP.StatScan.ReadItemText(entry.itemLink))
            if AP.StatScan.SameStatSet(set, pending.statSet) then
                table.insert(matches, entry)
            end
        end
        mergeIntoProvider(provider, matches)
    end)
end

-- Search same slot/armor type within +/- LEVEL_RANGE in the background; safe on the shared scanner because the selling tab's own name search has just finished.
local function runComparableSearch(pending)
    watch.scanEntries = {}
    watch.scanning = true
    watch.scanToken = pending.token
    Auctionator.EventBus:Register(scanListener, scanEvents())

    local ok = pcall(Auctionator.AH.QueryAuctionItems, {
        searchString = "",
        minLevel = pending.minLevel,
        maxLevel = pending.maxLevel,
        itemClassFilters = Auctionator.Search.GetItemClassCategories(pending.categoryKey) or {},
        isExact = false,
    })
    if not ok then stopScan() end
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
    watch.token = watch.token + 1
    stopScan()

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

local function receiveEvent(_, eventName, eventData, arg3)
    local sellingEvents = Auctionator.Selling.Events
    local buyingEvents = Auctionator.Buying.Events
    local AH = Auctionator.AH.Events

    if eventName == sellingEvents.StartFakeBuyLoading then
        local link = eventData and eventData.itemLink
        if not link then return end
        trackSaleItem(link)
        if not AP.Settings.checkOtherItems then return end
        -- Skip the rapid repeat fires for the item just handled; a later re-drop still re-runs.
        if link == watch.lastLink and watch.lastProcessAt
            and (GetTime() - watch.lastProcessAt) < REDROP_DEBOUNCE then
            return
        end
        startForItem(link)

    elseif eventName == sellingEvents.ClearBagItem then
        watch.token = watch.token + 1
        watch.lastLink = nil
        watch.pending = nil
        trackSaleItem(nil)
        stopScan()

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
}, receiveEvent)

local function ensureCheckbox()
    if AP.checkOtherItemsButton then return true end
    local sellingFrame = _G.AuctionatorSellingFrame
    local anchor = sellingFrame and (sellingFrame.BagInset or sellingFrame)
    if not sellingFrame or not anchor then return false end

    local check = CreateFrame(
        "CheckButton", "AuctionatorPlusCheckSimilarItems", sellingFrame, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 4, 3)
    check:SetChecked(AP.Settings.checkOtherItems)

    local label = check:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    label:SetText("Check Similar Items")

    -- "Same Stats" narrows to the same primary-stat set; only meaningful while similar items are shown, so it tracks the box above.
    local sameStats = CreateFrame(
        "CheckButton", "AuctionatorPlusSameStats", sellingFrame, "UICheckButtonTemplate")
    sameStats:SetSize(24, 24)
    sameStats:SetPoint("LEFT", label, "RIGHT", 12, 0)
    sameStats:SetChecked(AP.Settings.sameStats)

    local sameStatsLabel = sameStats:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sameStatsLabel:SetPoint("LEFT", sameStats, "RIGHT", 2, 0)
    sameStatsLabel:SetText("Same Stats")

    check.apLabel = label
    sameStats.apLabel = sameStatsLabel

    check:SetScript("OnClick", function(self)
        AP.Settings.checkOtherItems = self:GetChecked() and true or false
        AP.SaveSettings()
        updateCheckboxState()
    end)
    check:SetMotionScriptsWhileDisabled(true)
    check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Check Similar Items")
        GameTooltip:AddLine(
            "When a gear item is placed for sale, also list other auctions of the same slot, armor type, and required level (+/-2) in the current prices panel.",
            1, 1, 1, true)
        if not watch.saleIsGear then
            GameTooltip:AddLine("Enabled while a piece of gear sits in the sale slot.", 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", GameTooltip_Hide)

    sameStats:SetScript("OnClick", function(self)
        AP.Settings.sameStats = self:GetChecked() and true or false
        AP.SaveSettings()
    end)
    sameStats:SetMotionScriptsWhileDisabled(true)
    sameStats:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Same Stats")
        GameTooltip:AddLine(
            "Only list similar items that carry the same stats as the item being sold (e.g. Agility and Stamina). Stat values are ignored.",
            1, 1, 1, true)
        if not watch.saleIsGear then
            GameTooltip:AddLine("Enabled while a piece of gear sits in the sale slot, with Check Similar Items on.", 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)
    sameStats:SetScript("OnLeave", GameTooltip_Hide)

    AP.checkOtherItemsButton = check
    AP.sameStatsButton = sameStats

    updateCheckboxState()

    return true
end

local function hookRefreshButton()
    if AP.refreshButtonHooked then return true end
    local sellingFrame = _G.AuctionatorSellingFrame
    local buyFrame = sellingFrame and sellingFrame.BuyFrame
    local currentPrices = buyFrame and buyFrame.CurrentPrices
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
