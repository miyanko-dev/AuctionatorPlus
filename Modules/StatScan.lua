local _, AP = ...

AP.StatScan = {}

-- Primary stats in display order, with Blizzard-localized labels; tokens match against the lowercased tooltip text ReadItemText returns.
AP.StatScan.STAT_ORDER = { "strength", "agility", "stamina", "intellect", "spirit" }

AP.StatScan.STAT_LABELS = {
    strength  = _G.SPELL_STAT1_NAME or "Strength",
    agility   = _G.SPELL_STAT2_NAME or "Agility",
    stamina   = _G.SPELL_STAT3_NAME or "Stamina",
    intellect = _G.SPELL_STAT4_NAME or "Intellect",
    spirit    = _G.SPELL_STAT5_NAME or "Spirit",
}

local STAT_TOKENS = {}
for key, label in pairs(AP.StatScan.STAT_LABELS) do
    STAT_TOKENS[key] = label:lower()
end
AP.StatScan.STAT_TOKENS = STAT_TOKENS

local SCAN_TIP_NAME = "AuctionatorPlusScanTooltip"
local scanTip

local function ensureScanTooltip()
    if scanTip then return scanTip end
    scanTip = CreateFrame("GameTooltip", SCAN_TIP_NAME, nil, "GameTooltipTemplate")
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    return scanTip
end

-- Read the full tooltip text for a link off a hidden scan tooltip (C_TooltipInfo does not exist on era), lowercased; nil while the item data is uncached.
function AP.StatScan.ReadItemText(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then return nil end

    local tip = ensureScanTooltip()
    tip:ClearLines()
    tip:SetHyperlink(itemLink)

    local lines = tip:NumLines() or 0
    if lines == 0 then return nil end

    local parts = {}
    for i = 1, lines do
        local left = _G[SCAN_TIP_NAME .. "TextLeft" .. i]
        local right = _G[SCAN_TIP_NAME .. "TextRight" .. i]
        if left then
            local text = left:GetText()
            if type(text) == "string" and text ~= "" then table.insert(parts, text) end
        end
        if right then
            local text = right:GetText()
            if type(text) == "string" and text ~= "" then table.insert(parts, text) end
        end
    end

    if #parts == 0 then return nil end
    return table.concat(parts, "\n"):lower()
end

-- Primary stats present on an item by plain substring match, robust to "+N Stat" and "Equip: ... Stat by N" forms.
function AP.StatScan.PrimaryStatSet(itemText)
    local present = {}
    if type(itemText) ~= "string" then return present end
    for key, token in pairs(STAT_TOKENS) do
        if itemText:find(token, 1, true) then present[key] = true end
    end
    return present
end

-- True when two primary-stat sets contain exactly the same stats (values ignored).
function AP.StatScan.SameStatSet(a, b)
    for key in pairs(a) do if not b[key] then return false end end
    for key in pairs(b) do if not a[key] then return false end end
    return true
end

-- Localized DPS phrase (e.g. "damage per second") from DPS_TEMPLATE, placeholder and parentheses stripped.
local dpsPhrase
local function getDpsPhrase()
    if dpsPhrase == nil then
        local template = _G.DPS_TEMPLATE
        if type(template) == "string" then
            dpsPhrase = strtrim((template:gsub("%%s", ""):gsub("[%(%)]", ""))):lower()
        else
            dpsPhrase = ""
        end
    end
    return dpsPhrase
end

-- Weapon DPS from the tooltip ("(37.5 damage per second)"), rounded so values compare cleanly; nil without a DPS line.
function AP.StatScan.ParseDPS(itemText)
    if type(itemText) ~= "string" then return nil end
    local phrase = getDpsPhrase()
    if phrase == "" then return nil end
    local number = itemText:match("([%d%.]+)%s+" .. phrase)
    local dps = number and tonumber(number)
    if not dps or dps <= 0 then return nil end
    return math.floor(dps + 0.5)
end

-- equipLoc, itemType, itemSubType for a link; nil when the item is not cached.
function AP.StatScan.GetEquipInfo(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then return nil end
    local _, _, _, _, _, itemType, itemSubType, _, equipLoc = C_Item.GetItemInfo(itemLink)
    if not equipLoc then return nil end
    return equipLoc, itemType, itemSubType
end
