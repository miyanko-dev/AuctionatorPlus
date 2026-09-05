local _, AP = ...

AP.StatScan = {}

-- Primary stats with Blizzard-localized labels; tokens match against the lowercased tooltip text ReadItemText returns.
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

-- Lines describing Use effects, procs or set bonuses carry digits but are not item stats; a shield's own "45 Block" line is its block value
local function isStatLine(line)
    if not line:find("%d") then return false end
    if line:find("^use:") or line:find("^chance on hit:") or line:find("set:", 1, true) then return false end
    return true
end

-- The amount a line grants: the number written before the stat's name ("+3 Stamina"), else the line's first number ("increased by 5", "restores 4 mana per 5 sec")
local function valueOf(line, token)
    local value = token and line:match("(%d+) " .. token) or line:match("%d+%.?%d*")
    return tonumber(value)
end

-- Primary stats, robust to "+N Stat", "Stat increased by N" and "+N to all attributes"
local function addPrimaryStats(line, present)
    if line:find("all attributes", 1, true) or line:find("all stats", 1, true) then
        for key in pairs(STAT_TOKENS) do present[key] = valueOf(line) end
        return
    end
    for key, token in pairs(STAT_TOKENS) do
        if line:find(token, 1, true) then present[key] = valueOf(line, token) end
    end
end

-- Spell schools as they appear in era school-damage and resistance lines
local SPELL_SCHOOLS = { "arcane", "fire", "frost", "holy", "nature", "shadow" }

-- Generic spell power wordings: Equip effects, random-suffix lines and the combined era stat
local SPELL_POWER_TOKENS = { "magical spells", "damage done by spells", "damage from spells", "damage and healing", "spell damage", "spell power" }

local function findAny(line, tokens)
    for _, token in ipairs(tokens) do
        if line:find(token, 1, true) then return true end
    end
    return false
end

-- Secondary stats per line, each stored with its amount; wordings verified against era 1.15.9 spell descriptions, enchantment names and GlobalStrings (English client). Creature-specific and form-only bonuses get their own keys so they never pass as plain attack power
local function addSecondaryStats(line, present)
    local value = valueOf(line)
    if findAny(line, { "when fighting", "damage done to", " vs ", "slaying", "against" }) then
        present.targetdamage = value
        return
    end
    if line:find("forms only", 1, true) then
        present.feralattackpower = value
        return
    end

    if line:find("attack power", 1, true) then
        present[line:find("ranged", 1, true) and "rangedattackpower" or "attackpower"] = value
    end
    if line:find("weapon damage", 1, true) or line:match("^%+%d+ damage$") or line:match("^%+%d+ weapon %a+ damage") then
        present.weapondamage = value
    end

    local schoolDamage = false
    for _, school in ipairs(SPELL_SCHOOLS) do
        if line:find(school, 1, true) and line:find("spell", 1, true) and line:find("damage", 1, true) then
            present[school .. "damage"] = value
            schoolDamage = true
        end
        if line:find(school .. " resistance", 1, true) then
            present[school .. "resistance"] = value
        end
    end
    if not schoolDamage and findAny(line, SPELL_POWER_TOKENS) then
        present.spellpower = value
    end
    if line:find("healing", 1, true) and not line:find("damage", 1, true) then
        present.healing = value
    end
    if line:find("all resistances", 1, true) then
        present.allresistance = value
    end

    local spell = line:find("spell", 1, true) or line:find("magic", 1, true)
    if line:find("critical", 1, true) then
        present[spell and "spellcrit" or "crit"] = value
    end
    if line:find("chance to hit", 1, true) or line:find("spell hit", 1, true) or line:match("%% hit") or line:match("hit %+%d") then
        if spell then present.spellhit = value end
        if not spell or findAny(line, { "melee", "weapon", "missile", "attacks" }) then present.hit = value end
    end

    if line:find("defense", 1, true) then present.defense = value end
    if line:find("dodge", 1, true) then present.dodge = value end
    if line:find("parry", 1, true) then present.parry = value end
    if line:find("block value", 1, true) or line:match("^%d+ block$") then
        present.blockvalue = value
    elseif line:find("block", 1, true) then
        present.block = value
    end

    local perFive = line:find("5 sec", 1, true)
    if perFive and line:find("mana", 1, true) then present.mp5 = value end
    if perFive and line:find("health", 1, true) then present.hp5 = value end
    if not perFive then
        if line:match("^%+%d+ health") or line:find("health is increased", 1, true) then present.health = value end
        if line:match("^%+%d+ mana$") then present.mana = value end
    end
    if line:match("^%+%d+ armor$") or line:find("armor increased by", 1, true) or line:find("increases your armor by", 1, true) then
        present.bonusarmor = value
    end

    -- "Increased Swords +3." style weapon and profession skills; Defense shares the form and is already counted
    local skill = line:match("^increased ([%a%- ]+) %+%d")
    if skill and skill ~= "defense" then present["skill:" .. skill] = value end
end

-- Stat map for an item's lowercased tooltip text, key to amount: primary stats plus every secondary stat family found on era gear
function AP.StatScan.FullStatSet(itemText)
    local present = {}
    if type(itemText) ~= "string" then return present end
    for rawLine in itemText:gmatch("[^\n]+") do
        local line = rawLine:gsub("^equip: ", "")
        if isStatLine(line) then
            addPrimaryStats(line, present)
            addSecondaryStats(line, present)
        end
    end
    return present
end

-- True when every stat in required is present in stats, each within the share of the required amount (values ignored when the share is nil).
function AP.StatScan.Covers(stats, required, sharePct)
    for key, amount in pairs(required) do
        local value = stats[key]
        if not value then return false end
        if sharePct and math.abs(value - amount) > amount * sharePct / 100 then return false end
    end
    return true
end

-- Number of distinct stats in a presence set.
function AP.StatScan.Count(stats)
    local count = 0
    for _ in pairs(stats) do count = count + 1 end
    return count
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
