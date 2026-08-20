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
    -- Re-own every scan: SetHyperlink can no-op on a tooltip already showing the same link.
    tip:SetOwner(WorldFrame, "ANCHOR_NONE")
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

-- Primary stats present on an item, robust to "+N Stat" and "Equip: ... Stat by N" forms. Only digit-bearing lines count, so item names like "Staff of Agility" never register as stats.
function AP.StatScan.PrimaryStatSet(itemText)
    local present = {}
    if type(itemText) ~= "string" then return present end
    for line in itemText:gmatch("[^\n]+") do
        if line:find("%d") then
            for key, token in pairs(STAT_TOKENS) do
                if line:find(token, 1, true) then present[key] = true end
            end
        end
    end
    return present
end

-- Spell schools as they appear in era school-damage and resistance tooltip lines.
local SPELL_SCHOOLS = { "arcane", "fire", "frost", "holy", "nature", "shadow" }

-- Secondary stats detected by presence; wordings verified against era client data (build 1.15.9), English clients only since equip-effect text has no localized globals.
local SECONDARY_TOKENS = {
    spellpower  = "magical spells",
    healing     = "healing done by spells",
    defense     = "defense",
    dodge       = "chance to dodge",
    parry       = "chance to parry",
    block       = "chance to block",
    mp5         = "mana per 5 sec",
    hp5         = "health per 5 sec",
}

local function addSecondaryStats(line, present)
    for key, token in pairs(SECONDARY_TOKENS) do
        if line:find(token, 1, true) then present[key] = true end
    end

    for _, school in ipairs(SPELL_SCHOOLS) do
        if line:find("damage done by " .. school .. " spells", 1, true) then
            present[school .. "damage"] = true
        end
        if line:find(school .. " resistance", 1, true) then
            present[school .. "resistance"] = true
        end
    end

    -- Split ranged from melee attack power, and crit and hit into melee and spell keys, off their shared phrases.
    if line:find("attack power", 1, true) then
        present[line:find("ranged", 1, true) and "rangedattackpower" or "attackpower"] = true
    end
    if line:find("critical strike", 1, true) then
        present[line:find("spells", 1, true) and "spellcrit" or "crit"] = true
    end
    if line:find("chance to hit", 1, true) then
        present[line:find("spells", 1, true) and "spellhit" or "hit"] = true
    end
end

-- Full stat presence set: primary stats plus attack power, school spell damage, crit, hit and the other era secondary stats.
function AP.StatScan.FullStatSet(itemText)
    local present = AP.StatScan.PrimaryStatSet(itemText)
    if type(itemText) ~= "string" then return present end
    for line in itemText:gmatch("[^\n]+") do
        if line:find("%d") then
            addSecondaryStats(line, present)
        end
    end
    return present
end

-- True when two stat sets contain exactly the same stats (values ignored).
function AP.StatScan.SameStatSet(a, b)
    for key in pairs(a) do if not b[key] then return false end end
    for key in pairs(b) do if not a[key] then return false end end
    return true
end

-- Lowercased match pattern built from CONTAINER_SLOTS ("%d Slot %s"), so bag tooltips parse in any locale.
local slotPattern
local function getSlotPattern()
    if slotPattern == nil then
        local template = _G.CONTAINER_SLOTS
        if type(template) == "string" then
            slotPattern = template:lower():gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
            slotPattern = slotPattern:gsub("%%%d?%$?d", "(%%d+)"):gsub("%%%d?%$?s", ".-")
        else
            slotPattern = "(%d+) slot"
        end
    end
    return slotPattern
end

-- Container slot count from the tooltip line ("16 Slot Bag"); nil when no such line exists.
function AP.StatScan.ParseSlotCount(itemText)
    if type(itemText) ~= "string" then return nil end
    local count = itemText:match(getSlotPattern())
    return count and tonumber(count)
end

-- Lowercased match pattern built from DPS_TEMPLATE ("(%s damage per second)"), so weapon tooltips parse in any locale.
local dpsPattern
local function getDpsPattern()
    if dpsPattern == nil then
        local template = _G.DPS_TEMPLATE
        if type(template) == "string" then
            dpsPattern = template:lower():gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
            dpsPattern = dpsPattern:gsub("%%%d?%$?s", "([%%d%%.,]+)")
        else
            dpsPattern = "%(([%d%.,]+) damage per second%)"
        end
    end
    return dpsPattern
end

-- Weapon damage per second from the tooltip line ("(10.5 damage per second)"), tolerant of comma decimals; nil when no such line exists.
function AP.StatScan.ParseDPS(itemText)
    if type(itemText) ~= "string" then return nil end
    local value = itemText:match(getDpsPattern())
    return value and tonumber((value:gsub(",", ".")))
end

-- equipLoc, itemType, itemSubType for a link; nil when the item is not cached.
function AP.StatScan.GetEquipInfo(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then return nil end
    local _, _, _, _, _, itemType, itemSubType, _, equipLoc = C_Item.GetItemInfo(itemLink)
    if not equipLoc then return nil end
    return equipLoc, itemType, itemSubType
end
