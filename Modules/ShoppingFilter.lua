local _, AP = ...

AP.ShoppingFilter = {}

-- Filterable stats in dialog order, physical column first; every key matches AP.ItemStats.FullStatSet
local STAT_ORDER = {
    "strength", "agility", "stamina", "intellect", "spirit",
    "attackpower", "rangedattackpower", "hit", "crit", "haste", "expertise", "armorpenetration", "defense",
    "spellpower", "healing", "spellhit", "spellcrit", "spellpenetration", "mp5",
    "arcanedamage", "firedamage", "frostdamage", "holydamage", "naturedamage", "shadowdamage",
}

-- Stats only gear with combat ratings carries in a parseable form; both clients define their strings, so the client's half decides through AP.ItemStats.RATED_GEAR
local RATED_STATS = { haste = true, expertise = true, armorpenetration = true, spellpenetration = true }

-- Labels are the client's own stat names, so they match the item tooltips in every locale
local FILTER_LABELS = {
    attackpower = ITEM_MOD_ATTACK_POWER_SHORT,
    rangedattackpower = ITEM_MOD_RANGED_ATTACK_POWER_SHORT,
    hit = ITEM_MOD_HIT_RATING_SHORT,
    crit = ITEM_MOD_CRIT_RATING_SHORT,
    haste = ITEM_MOD_HASTE_RATING_SHORT,
    expertise = ITEM_MOD_EXPERTISE_RATING_SHORT,
    armorpenetration = ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT,
    defense = ITEM_MOD_DEFENSE_SKILL_RATING_SHORT,
    spellpower = ITEM_MOD_SPELL_POWER_SHORT,
    healing = ITEM_MOD_SPELL_HEALING_DONE_SHORT,
    spellhit = ITEM_MOD_HIT_SPELL_RATING_SHORT,
    spellcrit = ITEM_MOD_CRIT_SPELL_RATING_SHORT,
    spellpenetration = ITEM_MOD_SPELL_PENETRATION_SHORT,
    mp5 = ITEM_MOD_MANA_REGENERATION_SHORT,
    arcanedamage = ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT,
    firedamage = ITEM_MOD_FIRE_DAMAGE_DONE_SHORT,
    frostdamage = ITEM_MOD_FROST_DAMAGE_DONE_SHORT,
    holydamage = ITEM_MOD_HOLY_DAMAGE_DONE_SHORT,
    naturedamage = ITEM_MOD_NATURE_DAMAGE_DONE_SHORT,
    shadowdamage = ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT,
}
for key, label in pairs(AP.ItemStats.STAT_LABELS) do
    FILTER_LABELS[key] = label
end

-- The stats this client offers, in dialog order, and the same set for lookups
local FILTER_ORDER, OFFERED = {}, {}
for _, key in ipairs(STAT_ORDER) do
    if FILTER_LABELS[key] and (AP.ItemStats.RATED_GEAR or not RATED_STATS[key]) then
        FILTER_ORDER[#FILTER_ORDER + 1] = key
        OFFERED[key] = true
    end
end

local BUTTON_GAP = 5
local FILTER_COLUMNS = 2
local FILTER_ROWS = math.ceil(#FILTER_ORDER / FILTER_COLUMNS)
local COLUMN_WIDTH = 208
local DROPDOWN_WIDTH = 120
local APPLY_WIDTH = 96
local DIALOG_WIDTH = 2 * AP.Panel.INSET + FILTER_COLUMNS * COLUMN_WIDTH

local filterButton, resetButton, dialog
local provider, originalAppend

-- Every entry Auctionator appended for the current search, in arrival order, so a filter change rebuilds the visible rows without a new search
local allEntries = {}

-- Bumps on every search start and refilter; stale item-load callbacks compare against it and drop out
local generation = 0

-- Offered stats of a saved filter; stats this client does not offer never constrain it
local function offeredStats(stats)
    local kept = {}
    for key in pairs(stats) do
        if OFFERED[key] then kept[key] = true end
    end
    return kept
end

-- Account-wide filter: { stats = { strength = true, ... }, logic = "AND"|"OR" }; nil when unset
local function activeFilter()
    local filter = AP.DB().shoppingStatFilter
    if type(filter) ~= "table" or type(filter.stats) ~= "table" then return nil end
    local stats = offeredStats(filter.stats)
    if not next(stats) then return nil end
    return { stats = stats, logic = filter.logic }
end

-- A school filter is also met by generic spell power, which boosts every school
local function hasStat(present, key)
    if present[key] then return true end
    return key:match("damage$") ~= nil and present.spellpower ~= nil
end

local function statsMatch(itemText, filter)
    local present = AP.ItemStats.FullStatSet(itemText)
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

-- Whether a result survives the filter: equipment must carry the chosen stats, while consumables, trade goods and rows without an item (missing-term placeholders) always stay. Second return asks for a retry once the item cache fills
local function entryMatches(entry, filter)
    local itemRef = AP.Bridge.ShoppingItemRef(entry)
    if not itemRef then return true, false end

    local classID = select(6, AP.ItemStats.InstantInfo(itemRef))
    if not AP.Bridge.IsEquipment(classID) then return true, false end

    local itemText = AP.ItemStats.Text(itemRef)
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

-- Re-append an uncached entry once its item data arrives, if it matches by then; the provider dedups by item, so double appends are safe
local function retryOnLoad(entry)
    local itemID = AP.ItemStats.InstantInfo(AP.Bridge.ShoppingItemRef(entry))
    if not itemID then return end

    local startedGeneration = generation
    Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
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
            kept[#kept + 1] = entry
        elseif needsLoad then
            retryOnLoad(entry)
        end
    end
    return kept
end

-- Rebuild the visible rows from the recorded entries under the current filter; Auctionator's search stays untouched
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

    -- GenerateMenu re-runs the radio setup so the button text reflects the applied value
    dialog.logicDropdown:GenerateMenu()
end

-- Parented to the shopping frame so it hides with the Auction House
local function buildDialog()
    local panel = AP.Panel
    dialog = panel.Create("AuctionatorPlusStatFilterDialog", "Stat Filter", DIALOG_WIDTH, AuctionatorShoppingFrame)

    dialog.statLogic = "AND"
    local logicDropdown = CreateFrame("DropdownButton", nil, dialog, "WowStyle1DropdownTemplate")
    logicDropdown:SetPoint("TOPLEFT", dialog, "TOPLEFT", panel.INSET, -panel.PAD_TOP)
    logicDropdown:SetSize(DROPDOWN_WIDTH, panel.ROW)
    MenuUtil.CreateRadioMenu(logicDropdown,
        function(value) return dialog.statLogic == value end,
        function(value) dialog.statLogic = value end,
        { "Match All", "AND" },
        { "Match Any", "OR" })
    dialog.logicDropdown = logicDropdown

    dialog.statChecks = {}
    for index, key in ipairs(FILTER_ORDER) do
        local check = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
        check:SetSize(panel.ROW, panel.ROW)
        local column = math.floor((index - 1) / FILTER_ROWS)
        local row = (index - 1) % FILTER_ROWS
        check:SetPoint("TOPLEFT", logicDropdown, "BOTTOMLEFT", column * COLUMN_WIDTH, -panel.GAP - row * panel.ROW)
        check.Text:SetFontObject("GameFontHighlight")
        check.Text:SetText(FILTER_LABELS[key])

        dialog.statChecks[key] = check
    end

    local applyButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    applyButton:SetSize(APPLY_WIDTH, panel.BUTTON_HEIGHT)
    applyButton:SetText("Apply")
    applyButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -panel.INSET, panel.INSET)
    applyButton:SetScript("OnClick", function()
        AP.DB().shoppingStatFilter = readControls()
        dialog:Hide()
        reapplyFilter()
    end)

    -- Dropdown row, stat grid, a section gap and the Apply row stack between the header clearance and the bottom inset
    dialog:SetHeight(panel.PAD_TOP + panel.ROW + panel.GAP + FILTER_ROWS * panel.ROW + panel.SECTION + panel.BUTTON_HEIGHT + panel.INSET)

    dialog:SetScript("OnShow", function()
        applyToControls(activeFilter())
    end)
end

-- Parented to the shopping full-scan button so both filter buttons follow its bottom-row spot and hide with it behind the buy screens
local function ensureButtons()
    if filterButton then return true end
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

-- Instance wrap, not a mixin hook: record the unfiltered entries and forward only survivors, leaving Auctionator's search pipeline untouched
local function installProviderFilter()
    if originalAppend then return true end

    provider = AuctionatorShoppingFrame and AuctionatorShoppingFrame.DataProvider
    if not provider or type(provider.AppendEntries) ~= "function" then return false end

    originalAppend = provider.AppendEntries
    provider.AppendEntries = function(self, entries, isLastSet)
        for _, entry in ipairs(entries) do
            allEntries[#allEntries + 1] = entry
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
