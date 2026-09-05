local _, AP = ...

AP.ShoppingFilter = {}

-- Filterable stats in dialog order, physical column first; every key matches AP.StatScan.FullStatSet.
local FILTER_ORDER = {
    "strength", "agility", "stamina", "intellect", "spirit",
    "attackpower", "rangedattackpower", "hit", "crit",
    "spellhit", "spellcrit", "spellpower", "healing", "mp5", "defense",
    "arcanedamage", "firedamage", "frostdamage", "holydamage", "naturedamage", "shadowdamage",
}

local FILTER_LABELS = {
    attackpower = "Attack Power",
    rangedattackpower = "Ranged Attack Power",
    hit = "Hit Chance",
    crit = "Crit Chance",
    spellhit = "Spell Hit Chance",
    spellcrit = "Spell Crit Chance",
    spellpower = "Spell Power",
    healing = "Healing",
    mp5 = "Mana per 5 sec",
    defense = "Defense",
    arcanedamage = "Arcane Spell Power",
    firedamage = "Fire Spell Power",
    frostdamage = "Frost Spell Power",
    holydamage = "Holy Spell Power",
    naturedamage = "Nature Spell Power",
    shadowdamage = "Shadow Spell Power",
}
for key, label in pairs(AP.StatScan.STAT_LABELS) do
    FILTER_LABELS[key] = label
end

local BUTTON_GAP = 5
local FILTER_COLUMNS = 2
local FILTER_ROWS = math.ceil(#FILTER_ORDER / FILTER_COLUMNS)
local COLUMN_WIDTH = 150
local STAT_ROW_HEIGHT = 26
local CONTROL_HEIGHT = 22
local DIALOG_WIDTH = 2 * AP.Panel.PAD + FILTER_COLUMNS * COLUMN_WIDTH

local filterButton, resetButton, dialog
local provider, originalAppend

-- Every entry Auctionator appended for the current search, in arrival order, so a filter change rebuilds the visible rows without a new search.
local allEntries = {}

-- Bumps on every search start and refilter; stale item-load callbacks compare against it and drop out.
local generation = 0

-- Account-wide filter: { stats = { strength = true, ... }, logic = "AND"|"OR" }; nil when unset.
local function activeFilter()
    local filter = AP.DB().shoppingStatFilter
    if type(filter) ~= "table" or type(filter.stats) ~= "table" or not next(filter.stats) then
        return nil
    end
    return filter
end

-- A school filter is also met by generic spell power, which boosts every school
local function hasStat(present, key)
    if present[key] then return true end
    return key:match("damage$") ~= nil and present.spellpower ~= nil
end

-- Match on the parsed stat presence set, so ranged attack power never counts as attack power and spell crit stays apart from melee crit.
local function statsMatch(itemText, filter)
    local present = AP.StatScan.FullStatSet(itemText)
    if filter.logic == "OR" then
        for key in pairs(filter.stats) do
            if hasStat(present, key) then return true end
        end
        return false
    end

    for key in pairs(filter.stats) do
        if not hasStat(present, key) then return false end
    end
    return true
end

-- Whether a result row survives the filter: equipment must carry the chosen stats, while consumables, trade goods and rows without an item link (missing-term placeholders) always stay. Second return asks for a retry once the item cache fills.
local function entryMatches(entry, filter)
    local link = entry.entries and entry.entries[1] and entry.entries[1].itemLink
    if not link then return true, false end

    local classID = select(6, C_Item.GetItemInfoInstant(link))
    if not Auctionator.Utilities.IsEquipment(classID) then return true, false end

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
    for _, key in ipairs(FILTER_ORDER) do
        if dialog.statChecks[key]:GetChecked() then
            stats[key] = true
        end
    end

    if not next(stats) then return nil end
    return { stats = stats, logic = dialog.statLogic }
end

local function applyToControls(filter)
    for _, key in ipairs(FILTER_ORDER) do
        dialog.statChecks[key]:SetChecked(filter and filter.stats[key])
    end
    dialog.statLogic = filter and filter.logic or "AND"

    -- GenerateMenu re-runs the radio setup so the button text reflects the applied value.
    dialog.logicDropdown:GenerateMenu()
end

-- Parented to the shopping frame so it hides with the Auction House
local function buildDialog()
    dialog = AP.Panel.Create("AuctionatorPlusStatFilterDialog", "Stat Filter", DIALOG_WIDTH, _G.AuctionatorShoppingFrame)

    dialog.statLogic = "AND"
    local logicDropdown = CreateFrame("DropdownButton", nil, dialog, "WowStyle1DropdownTemplate")
    logicDropdown:SetPoint("TOPLEFT", dialog, "TOPLEFT", AP.Panel.PAD, -AP.Panel.PAD_TOP)
    logicDropdown:SetSize(120, CONTROL_HEIGHT)
    MenuUtil.CreateRadioMenu(logicDropdown,
        function(value) return dialog.statLogic == value end,
        function(value) dialog.statLogic = value end,
        { "Match All", "AND" },
        { "Match Any", "OR" })
    dialog.logicDropdown = logicDropdown

    dialog.statChecks = {}
    for index, key in ipairs(FILTER_ORDER) do
        local check = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        local column = math.floor((index - 1) / FILTER_ROWS)
        local row = (index - 1) % FILTER_ROWS
        check:SetPoint("TOPLEFT", logicDropdown, "BOTTOMLEFT",
            -2 + column * COLUMN_WIDTH, -AP.Panel.TEXT_GAP - row * STAT_ROW_HEIGHT)

        local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", check, "RIGHT", 2, 0)
        label:SetText(FILTER_LABELS[key])

        dialog.statChecks[key] = check
    end

    local applyButton = CreateFrame("Button", nil, dialog, "UIPanelDynamicResizeButtonTemplate")
    applyButton:SetText("Apply")
    DynamicResizeButton_Resize(applyButton)
    applyButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -AP.Panel.PAD, AP.Panel.PAD)
    applyButton:SetScript("OnClick", function()
        AP.DB().shoppingStatFilter = readControls()
        dialog:Hide()
        reapplyFilter()
    end)

    -- Dropdown row, stat grid, a section gap and the Apply row stack inside the padding
    dialog:SetHeight(AP.Panel.PAD_TOP + CONTROL_HEIGHT + AP.Panel.TEXT_GAP + FILTER_ROWS * STAT_ROW_HEIGHT
        + AP.Panel.SECTION_GAP + CONTROL_HEIGHT + AP.Panel.PAD)

    dialog:SetScript("OnShow", function()
        applyToControls(activeFilter())
    end)
end

local function ensureButtons()
    if filterButton then return true end

    -- Parent to the full-scan button so both filter buttons follow its bottom-row spot and hide with it behind the buy screen.
    local fullScan = AP.shoppingScanButton
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
        AP.DB().shoppingStatFilter = nil
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
    local buttonsReady = ensureButtons()
    local providerReady = installProviderFilter()
    return buttonsReady and providerReady
end
