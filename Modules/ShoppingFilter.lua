local _, AP = ...

AP.ShoppingFilter = {}

local STAT_ORDER = AP.StatScan.STAT_ORDER
local STAT_LABELS = AP.StatScan.STAT_LABELS
local STAT_TOKENS = AP.StatScan.STAT_TOKENS

local ARMOR_CLASS = Enum.ItemClass.Armor
local BUTTON_GAP = 5
local DIALOG_WIDTH = 210
-- 86 ButtonFrameTemplate inset chrome + 42 dropdown row + 26 per stat row + 38 apply row keeps every control inside the inset.
local DIALOG_HEIGHT = 86 + 42 + #STAT_ORDER * 26 + 38

local filterButton, resetButton, dialog
local provider, originalAppend

-- Every entry Auctionator appended for the current search, in arrival order, so a filter change rebuilds the visible rows without a new search.
local allEntries = {}

-- Bumps on every search start and refilter; stale item-load callbacks compare against it and drop out.
local generation = 0

local function accountDB()
    if type(AuctionatorPlusAccountDB) ~= "table" then
        AuctionatorPlusAccountDB = {}
    end
    return AuctionatorPlusAccountDB
end

-- Account-wide filter: { stats = { strength = true, ... }, logic = "AND"|"OR" }; nil when unset.
local function activeFilter()
    local filter = accountDB().shoppingStatFilter
    if type(filter) ~= "table" or type(filter.stats) ~= "table" or not next(filter.stats) then
        return nil
    end
    return filter
end

-- Match by plain substring so suffix gear and equip-effect stats count; structured stat parsing silently dropped those.
local function statsMatch(itemText, filter)
    if filter.logic == "OR" then
        for key in pairs(filter.stats) do
            if itemText:find(STAT_TOKENS[key], 1, true) then return true end
        end
        return false
    end

    for key in pairs(filter.stats) do
        if not itemText:find(STAT_TOKENS[key], 1, true) then return false end
    end
    return true
end

-- Whether a result row survives the filter: armor-class items with the chosen stats; rows without an item link (missing-term placeholders) always stay. Second return asks for a retry once the item cache fills.
local function entryMatches(entry, filter)
    local link = entry.entries and entry.entries[1] and entry.entries[1].itemLink
    if not link then return true, false end

    local classID = select(6, C_Item.GetItemInfoInstant(link))
    if classID ~= ARMOR_CLASS then return false, false end

    local itemText = AP.StatScan.ReadItemText(link)
    if not itemText then return false, true end

    return statsMatch(itemText, filter), false
end

local function updateButtonState()
    if not filterButton then return end

    local filter = activeFilter()
    if filter then
        local count = 0
        for _ in pairs(filter.stats) do count = count + 1 end
        filterButton:SetText(("Filter (%d)"):format(count))
    else
        filterButton:SetText("Filter")
    end
    DynamicResizeButton_Resize(filterButton)
    resetButton:SetEnabled(filter ~= nil)
end

-- Re-append an uncached entry once its item data arrives, if it matches by then; the provider dedups by item key, so double appends are safe.
local function retryOnLoad(entry)
    local entryItem = Item:CreateFromItemLink(entry.entries[1].itemLink)
    if entryItem:IsItemEmpty() then return end

    local startedGeneration = generation
    entryItem:ContinueOnItemLoad(function()
        if generation ~= startedGeneration then return end

        local filter = activeFilter()
        if filter and not entryMatches(entry, filter) then return end
        originalAppend(provider, { entry }, provider.searchCompleted)
    end)
end

local function filterEntries(entries)
    local filter = activeFilter()
    if not filter then return entries end

    local kept = {}
    for _, entry in ipairs(entries) do
        local matched, needsLoad = entryMatches(entry, filter)
        if matched then
            table.insert(kept, entry)
        elseif needsLoad then
            retryOnLoad(entry)
        end
    end
    return kept
end

-- Rebuild the visible rows from the recorded entries under the current filter; Auctionator's search stays untouched.
local function reapplyFilter()
    updateButtonState()
    if not originalAppend then return end

    generation = generation + 1
    local searchWasComplete = provider.searchCompleted
    provider:Reset()
    originalAppend(provider, filterEntries(allEntries), searchWasComplete)
end

local function readControls()
    local stats = {}
    for _, key in ipairs(STAT_ORDER) do
        if dialog.statChecks[key]:GetChecked() then
            stats[key] = true
        end
    end

    if not next(stats) then return nil end
    return { stats = stats, logic = dialog.statLogic }
end

local function applyToControls(filter)
    for _, key in ipairs(STAT_ORDER) do
        dialog.statChecks[key]:SetChecked(filter and filter.stats[key])
    end
    dialog.statLogic = filter and filter.logic or "AND"
    -- GenerateMenu re-runs the radio setup so the button text reflects the applied value.
    dialog.logicDropdown:GenerateMenu()
end

local function buildDialog()
    dialog = CreateFrame("Frame", "AuctionatorPlusStatFilterDialog", _G.AuctionatorShoppingFrame, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(dialog)
    dialog:SetSize(DIALOG_WIDTH, DIALOG_HEIGHT)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetTitle("Stat Filter")
    dialog:EnableMouse(true)
    tinsert(UISpecialFrames, dialog:GetName())

    dialog.statLogic = "AND"
    local logicDropdown = CreateFrame("DropdownButton", nil, dialog, "WowStyle1DropdownTemplate")
    logicDropdown:SetPoint("TOPLEFT", dialog.Inset, "TOPLEFT", 12, -12)
    logicDropdown:SetWidth(120)
    MenuUtil.CreateRadioMenu(logicDropdown,
        function(value) return dialog.statLogic == value end,
        function(value) dialog.statLogic = value end,
        { "Match All", "AND" },
        { "Match Any", "OR" })
    dialog.logicDropdown = logicDropdown

    dialog.statChecks = {}
    local previous = logicDropdown
    for index, key in ipairs(STAT_ORDER) do
        local check = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        if index == 1 then
            check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", -2, -6)
        else
            check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -2)
        end

        local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", check, "RIGHT", 2, 0)
        label:SetText(STAT_LABELS[key])

        dialog.statChecks[key] = check
        previous = check
    end

    local applyButton = CreateFrame("Button", nil, dialog, "UIPanelDynamicResizeButtonTemplate")
    applyButton:SetText("Apply")
    DynamicResizeButton_Resize(applyButton)
    applyButton:SetPoint("BOTTOMRIGHT", dialog.Inset, "BOTTOMRIGHT", -10, 10)
    applyButton:SetScript("OnClick", function()
        accountDB().shoppingStatFilter = readControls()
        dialog:Hide()
        reapplyFilter()
    end)

    dialog:SetScript("OnShow", function()
        applyToControls(activeFilter())
    end)

    -- Frames spawn visible; start hidden so the Filter button's first toggle shows the dialog.
    dialog:Hide()
end

local function ensureButtons()
    if filterButton then return true end

    -- Parent to the full-scan button so both filter buttons follow its bottom-row spot and hide with it behind the buy screen.
    local fullScan = AP.fullScanShoppingButton
    if not fullScan then return false end

    filterButton = CreateFrame("Button", nil, fullScan, "UIPanelDynamicResizeButtonTemplate")
    filterButton:SetPoint("LEFT", fullScan, "RIGHT", BUTTON_GAP, 0)
    filterButton:SetScript("OnClick", function()
        if not dialog then buildDialog() end
        dialog:SetShown(not dialog:IsShown())
    end)

    resetButton = CreateFrame("Button", nil, fullScan, "UIPanelDynamicResizeButtonTemplate")
    resetButton:SetText("Reset Filter")
    DynamicResizeButton_Resize(resetButton)
    resetButton:SetPoint("LEFT", filterButton, "RIGHT", BUTTON_GAP, 0)
    resetButton:SetScript("OnClick", function()
        accountDB().shoppingStatFilter = nil
        if dialog then dialog:Hide() end
        reapplyFilter()
    end)

    updateButtonState()
    return true
end

-- Instance wrap, not a mixin hook: record the unfiltered entries and forward only survivors, leaving Auctionator's search pipeline untouched.
local function installProviderFilter()
    if originalAppend then return true end

    local shoppingFrame = _G.AuctionatorShoppingFrame
    provider = shoppingFrame and shoppingFrame.DataProvider
    if not provider or type(provider.AppendEntries) ~= "function" then return false end

    originalAppend = provider.AppendEntries
    provider.AppendEntries = function(self, entries, isLastSet)
        for _, entry in ipairs(entries) do
            table.insert(allEntries, entry)
        end
        return originalAppend(self, filterEntries(entries), isLastSet)
    end
    return true
end

AP.Bridge.Listen({ Auctionator.Shopping.Tab.Events.SearchStart }, function()
    generation = generation + 1
    allEntries = {}
end)

function AP.ShoppingFilter.Ensure()
    -- Legacy per-term store from the removed shopping-list integration.
    accountDB().statFilters = nil

    local buttonsReady = ensureButtons()
    local providerReady = installProviderFilter()
    return buttonsReady and providerReady
end
