local _, AP = ...

-- Stat parsing for both clients; each client's half supplies AP.ItemStats.Text (the item's lowercased tooltip text) and AP.ItemStats.RATED_GEAR
AP.ItemStats = {}

-- Primary stats with Blizzard-localized labels; tokens match against the lowercased tooltip text
AP.ItemStats.STAT_LABELS = {
    strength  = SPELL_STAT1_NAME,
    agility   = SPELL_STAT2_NAME,
    stamina   = SPELL_STAT3_NAME,
    intellect = SPELL_STAT4_NAME,
    spirit    = SPELL_STAT5_NAME,
}

local STAT_TOKENS = {}
for key, label in pairs(AP.ItemStats.STAT_LABELS) do
    STAT_TOKENS[key] = label:lower()
end

-- GetItemInfoInstant for a link, an item string or an auction item key; nil for anything else
function AP.ItemStats.InstantInfo(itemRef)
    local item = type(itemRef) == "table" and itemRef.itemID or itemRef
    if not item then return nil end
    return C_Item.GetItemInfoInstant(item)
end

local function escapePattern(text)
    return (text:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"))
end

-- Lua pattern for a client stat string: %c is the sign and %s or %d the amount, since Era prints primary stats as "%c%d Agility" and Forever as "%c%s Agility". Specifiers are marked before escaping so the text around them stays literal
local function modPattern(format)
    local marked = format:lower():gsub("%%c", "\1"):gsub("%%%d?%$?[sd]", "\2")
    local pattern = escapePattern(marked):gsub("\1", "[+-]"):gsub("\2", "([%%d%%.,]+)")
    return "^" .. pattern .. "$"
end

-- Stat suffixes of the client's ITEM_MOD_<name> strings; skill bonuses share keys with the vanilla "Increased Swords +3." lines
local MOD_STATS = {
    STRENGTH = "strength", AGILITY = "agility", STAMINA = "stamina", INTELLECT = "intellect", SPIRIT = "spirit",
    HEALTH = "health", MANA = "mana", EXTRA_ARMOR = "bonusarmor",
    HEALTH_REGEN = "hp5", HEALTH_REGENERATION = "hp5", MANA_REGENERATION = "mp5",
    ATTACK_POWER = "attackpower", RANGED_ATTACK_POWER = "rangedattackpower", FERAL_ATTACK_POWER = "feralattackpower",
    HIT_RATING = "hit", HIT_MELEE_RATING = "hit", HIT_RANGED_RATING = "hit", HIT_SPELL_RATING = "spellhit",
    CRIT_RATING = "crit", CRIT_MELEE_RATING = "crit", CRIT_RANGED_RATING = "crit", CRIT_SPELL_RATING = "spellcrit",
    HASTE_RATING = "haste", EXPERTISE_RATING = "expertise", ARMOR_PENETRATION_RATING = "armorpenetration",
    SPELL_POWER = "spellpower", SPELL_DAMAGE_DONE = "spellpower", SPELL_HEALING_DONE = "healing",
    PHYSICAL_DAMAGE_DONE = "physicaldamage", ARCANE_DAMAGE_DONE = "arcanedamage", FIRE_DAMAGE_DONE = "firedamage",
    FROST_DAMAGE_DONE = "frostdamage", HOLY_DAMAGE_DONE = "holydamage", NATURE_DAMAGE_DONE = "naturedamage",
    SHADOW_DAMAGE_DONE = "shadowdamage",
    SPELL_PENETRATION = "spellpenetration", ARCANE_PENETRATION = "arcanepenetration", FIRE_PENETRATION = "firepenetration",
    FROST_PENETRATION = "frostpenetration", NATURE_PENETRATION = "naturepenetration", SHADOW_PENETRATION = "shadowpenetration",
    SPELL_RESISTANCE_ALL_SCHOOLS = "spellresistance",
    DEFENSE_SKILL_RATING = "defense", DODGE_RATING = "dodge", PARRY_RATING = "parry",
    BLOCK_RATING = "block", BLOCK_VALUE = "blockvalue",
    HIT_TAKEN_RATING = "hitavoidance", HIT_TAKEN_MELEE_RATING = "hitavoidance", HIT_TAKEN_RANGED_RATING = "hitavoidance",
    HIT_TAKEN_SPELL_RATING = "hitavoidance", CRIT_TAKEN_RATING = "critavoidance", CRIT_TAKEN_MELEE_RATING = "critavoidance",
    CRIT_TAKEN_RANGED_RATING = "critavoidance", CRIT_TAKEN_SPELL_RATING = "critavoidance", RESILIENCE_RATING = "resilience",
    AXES = "skill:axes", TWOHANDED_AXES = "skill:twohandedaxes", BOWS = "skill:bows", CROSSBOWS = "skill:crossbows",
    DAGGERS = "skill:daggers", DUAL_WIELD = "skill:dualwield", FIST_WEAPONS = "skill:fistweapons", GUNS = "skill:guns",
    MACES = "skill:maces", TWOHANDED_MACES = "skill:twohandedmaces", POLEARMS = "skill:polearms", STAVES = "skill:staves",
    SWORDS = "skill:swords", TWOHANDED_SWORDS = "skill:twohandedswords", THROWN = "skill:thrown", WANDS = "skill:wands",
    ALCHEMY = "skill:alchemy", BLACKSMITHING = "skill:blacksmithing", COOKING = "skill:cooking", ENCHANTING = "skill:enchanting",
    ENGINEERING = "skill:engineering", FIRST_AID = "skill:firstaid", FISHING = "skill:fishing", HERBALISM = "skill:herbalism",
    JEWELCRAFTING = "skill:jewelcrafting", LEATHERWORKING = "skill:leatherworking", MINING = "skill:mining",
    SKINNING = "skill:skinning", TAILORING = "skill:tailoring",
}

-- Each stat line in both forms the client prints: long "increases your haste by 12." and short "+12 haste". Built from the client's own strings, so they parse in any locale and a stat only exists where the client has its string
local MOD_PATTERNS = {}
for name, key in pairs(MOD_STATS) do
    local long, short = _G["ITEM_MOD_" .. name], _G["ITEM_MOD_" .. name .. "_SHORT"]
    if long then
        MOD_PATTERNS[#MOD_PATTERNS + 1] = { modPattern(long), key }
    end
    if short then
        MOD_PATTERNS[#MOD_PATTERNS + 1] = { "^[+-]([%d%.,]+) " .. escapePattern(short:lower()) .. "$", key }
    end
end

-- Key and whole amount of a line in the client's stat wording; nil for any other line
local function modStat(line)
    for _, entry in ipairs(MOD_PATTERNS) do
        local amount = line:match(entry[1])
        if amount then return entry[2], tonumber((amount:gsub("%D", ""))) end
    end
    return nil
end

-- Leading text of a format string up to its %s, escaped for a pattern
local function prefixOf(format)
    return escapePattern(format:lower():match("^(.-)%%s"))
end

local EQUIP_PREFIX = "^" .. escapePattern(ITEM_SPELL_TRIGGER_ONEQUIP:lower()) .. " ?"

-- Active set bonuses print "Set: ...", inactive ones "(2) Set: ..."; ITEM_SET_BONUS_GRAY keeps its %d, which the pattern reads as the single-digit piece count
local SKIPPED_PREFIXES = {
    escapePattern(ITEM_SPELL_TRIGGER_ONUSE:lower()),
    escapePattern(ITEM_SPELL_TRIGGER_ONPROC:lower()),
    prefixOf(ITEM_SET_BONUS),
    prefixOf(ITEM_SET_BONUS_GRAY),
}

-- Lines describing Use effects, procs or set bonuses carry digits but are not item stats; a shield's own "45 Block" line is its block value
local function isStatLine(line)
    if not line:find("%d") then return false end
    for _, prefix in ipairs(SKIPPED_PREFIXES) do
        if line:find("^" .. prefix) then return false end
    end
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

-- Spell schools as they appear in vanilla school-damage and resistance lines
local SPELL_SCHOOLS = { "arcane", "fire", "frost", "holy", "nature", "shadow" }

-- Generic spell power wordings: Equip effects, random-suffix lines and the combined stat
local SPELL_POWER_TOKENS = { "magical spells", "damage done by spells", "damage from spells", "damage and healing", "spell damage", "spell power" }

local function findAny(line, tokens)
    for _, token in ipairs(tokens) do
        if line:find(token, 1, true) then return true end
    end
    return false
end

-- Secondary stats from Equip spell wordings the client strings do not cover, each stored with its amount; wordings follow the vanilla item set (English client). Creature-specific and form-only bonuses get their own keys so they never pass as plain attack power
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

    -- "Increased Swords +3." style weapon and profession skills, keyed like the client's skill strings; Defense shares the form and is already counted
    local skill = line:match("^increased ([%a%- ]+) %+%d")
    if skill and skill ~= "defense" then present["skill:" .. skill:gsub("[%- ]", "")] = value end
end

-- Stat map for an item's lowercased tooltip text, key to amount; the client's own stat wording wins, older Equip wordings fall back to the heuristics
function AP.ItemStats.FullStatSet(itemText)
    local present = {}
    if type(itemText) ~= "string" then return present end
    for rawLine in itemText:gmatch("[^\n]+") do
        local line = rawLine:gsub(EQUIP_PREFIX, "")
        local key, amount = modStat(line)
        if key then
            present[key] = amount
        elseif isStatLine(line) then
            addPrimaryStats(line, present)
            addSecondaryStats(line, present)
        end
    end
    return present
end

-- True when every stat in required is present in stats, each within the share of the required amount (values ignored when the share is nil)
function AP.ItemStats.Covers(stats, required, sharePct)
    for key, amount in pairs(required) do
        local value = stats[key]
        if not value then return false end
        if sharePct and math.abs(value - amount) > amount * sharePct / 100 then return false end
    end
    return true
end

function AP.ItemStats.Count(stats)
    local count = 0
    for _ in pairs(stats) do count = count + 1 end
    return count
end

-- Turn a Blizzard format string into a lowercased Lua pattern, so bag and weapon tooltips parse in any locale
local function patternFrom(template, numberCapture)
    local pattern = template:lower():gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
    pattern = pattern:gsub("%%%d?%$?d", numberCapture and "(%%d+)" or "%%d+")
    return (pattern:gsub("%%%d?%$?s", numberCapture and ".-" or "([%%d%%.,]+)"))
end

-- CONTAINER_SLOTS is "%d Slot %s"
local slotPattern

-- Container slot count from the "16 Slot Bag" line; nil when no such line exists
function AP.ItemStats.ParseSlotCount(itemText)
    if type(itemText) ~= "string" then return nil end
    slotPattern = slotPattern or patternFrom(CONTAINER_SLOTS, true)
    local count = itemText:match(slotPattern)
    return count and tonumber(count)
end

-- DPS_TEMPLATE is "(%s damage per second)"
local dpsPattern

-- Weapon damage per second from the "(10.5 damage per second)" line, tolerant of comma decimals; nil when no such line exists
function AP.ItemStats.ParseDPS(itemText)
    if type(itemText) ~= "string" then return nil end
    dpsPattern = dpsPattern or patternFrom(DPS_TEMPLATE, false)
    local value = itemText:match(dpsPattern)
    return value and tonumber((value:gsub(",", ".")))
end

-- Required character level for a link, an item string or an item key; nil while the item is uncached
function AP.ItemStats.RequiredLevel(itemRef)
    local item = type(itemRef) == "table" and itemRef.itemID or itemRef
    return select(5, C_Item.GetItemInfo(item))
end
