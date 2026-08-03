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

-- True when two primary-stat sets contain exactly the same stats (values ignored).
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

-- equipLoc, itemType, itemSubType for a link; nil when the item is not cached.
function AP.StatScan.GetEquipInfo(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then return nil end
    local _, _, _, _, _, itemType, itemSubType, _, equipLoc = C_Item.GetItemInfo(itemLink)
    if not equipLoc then return nil end
    return equipLoc, itemType, itemSubType
end
