FF.StatScan = {}

local SCAN_TIP_NAME = "FFStatScanTooltip"
local scanTip

local function EnsureScanTooltip()
  if scanTip then return scanTip end
  scanTip = CreateFrame("GameTooltip", SCAN_TIP_NAME, nil, "GameTooltipTemplate")
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  return scanTip
end

local function ReadTooltipInfo(itemLink)
  if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil end
  local tipInfo = C_TooltipInfo.GetHyperlink(itemLink)
  if not tipInfo or not tipInfo.lines or #tipInfo.lines == 0 then return nil end
  local parts = {}
  for _, line in ipairs(tipInfo.lines) do
    -- leftText/rightText are only populated after the line args are surfaced.
    if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(line) end
    local left = line.leftText
    local right = line.rightText
    if type(left) == "string" and left ~= "" then table.insert(parts, left) end
    if type(right) == "string" and right ~= "" then table.insert(parts, right) end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, "\n"):lower()
end

local function ReadScanTooltip(itemLink)
  local tip = EnsureScanTooltip()
  tip:ClearLines()
  tip:SetHyperlink(itemLink)
  local lines = tip:NumLines() or 0
  if lines == 0 then return nil end
  local parts = {}
  for i = 1, lines do
    local left = _G[SCAN_TIP_NAME .. "TextLeft" .. i]
    local right = _G[SCAN_TIP_NAME .. "TextRight" .. i]
    if left then
      local t = left:GetText()
      if type(t) == "string" and t ~= "" then table.insert(parts, t) end
    end
    if right then
      local t = right:GetText()
      if type(t) == "string" and t ~= "" then table.insert(parts, t) end
    end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, "\n"):lower()
end

function FF.StatScan.ReadItemText(itemLink)
  if type(itemLink) ~= "string" or itemLink == "" then return nil end
  local text = ReadTooltipInfo(itemLink)
  if text and text:find("%S") then return text end
  return ReadScanTooltip(itemLink)
end

local function ItemIDFromLink(itemLink)
  if type(itemLink) ~= "string" then return nil end
  local id = itemLink:match("|Hitem:(%d+)") or itemLink:match("^item:(%d+)")
  return id and tonumber(id) or nil
end

local function ResolveLink(entry, callback)
  if not entry then callback(nil); return end
  if entry.itemLink then callback(entry.itemLink); return end
  local id = entry.itemKey and entry.itemKey.itemID
  if id then
    local link = select(2, C_Item.GetItemInfo(id))
    if link then callback(link); return end
    local item = Item:CreateFromItemID(id)
    if item and not item:IsItemEmpty() then
      item:ContinueOnItemLoad(function()
        callback(select(2, C_Item.GetItemInfo(id)))
      end)
      return
    end
  end
  callback(nil)
end

-- Parse stat lines from already-lowercased tooltip text into a
-- { [statName] = value } map. Handles two Classic formats:
--   - intrinsic: "+5 strength"
--   - equip effect: "equip: increases your strength by 5" (with "your" optional)
function FF.StatScan.ParseStatLines(itemText)
  local stats = {}
  if type(itemText) ~= "string" then return stats end
  for line in itemText:gmatch("[^\n]+") do
    local value, name = line:match("^%s*%+(%d+)%s+(%a[%a%s]-)%s*$")
    if value and name then
      name = strtrim(name)
      stats[name] = (stats[name] or 0) + tonumber(value)
    else
      local equipName, equipValue = line:match("increases%s+(.-)%s+by%s+(%d+)")
      if equipName and equipValue then
        equipName = equipName:gsub("^your%s+", "")
        equipName = strtrim(equipName)
        if equipName ~= "" and equipName:match("^%a[%a%s]*$") then
          stats[equipName] = (stats[equipName] or 0) + tonumber(equipValue)
        end
      end
    end
  end
  return stats
end

-- Primary stats keyed to their lowercased tooltip word, for presence checks.
local PRIMARY_STATS = {
  strength  = (_G.SPELL_STAT1_NAME or "Strength"):lower(),
  agility   = (_G.SPELL_STAT2_NAME or "Agility"):lower(),
  stamina   = (_G.SPELL_STAT3_NAME or "Stamina"):lower(),
  intellect = (_G.SPELL_STAT4_NAME or "Intellect"):lower(),
  spirit    = (_G.SPELL_STAT5_NAME or "Spirit"):lower(),
}

-- The set of primary stats present on an item, by plain substring match on the
-- lowercased tooltip text (robust to "+N Stat" and "Equip: ... Stat by N" forms).
function FF.StatScan.PrimaryStatSet(itemText)
  local present = {}
  if type(itemText) ~= "string" then return present end
  for key, token in pairs(PRIMARY_STATS) do
    if itemText:find(token, 1, true) then present[key] = true end
  end
  return present
end

-- True when two primary-stat sets contain exactly the same stats (values ignored).
function FF.StatScan.SameStatSet(a, b)
  for key in pairs(a) do if not b[key] then return false end end
  for key in pairs(b) do if not a[key] then return false end end
  return true
end

-- Localized DPS phrase (e.g. "damage per second") derived from DPS_TEMPLATE,
-- with the format placeholder and parentheses stripped.
local dpsPhrase
function FF.StatScan.DpsPhrase()
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

-- Weapon DPS read from the tooltip ("(37.5 damage per second)"), rounded to an
-- integer so values compare cleanly. nil for items without a DPS line.
function FF.StatScan.ParseDPS(itemText)
  if type(itemText) ~= "string" then return nil end
  local phrase = FF.StatScan.DpsPhrase()
  if phrase == "" then return nil end
  local number = itemText:match("([%d%.]+)%s+" .. phrase)
  local dps = number and tonumber(number)
  if not dps or dps <= 0 then return nil end
  return math.floor(dps + 0.5)
end

-- equipLoc, itemType, itemSubType for a link; nil when the item is not cached.
function FF.StatScan.GetEquipInfo(itemLink)
  if type(itemLink) ~= "string" or itemLink == "" then return nil end
  local _, _, _, _, _, itemType, itemSubType, _, equipLoc = GetItemInfo(itemLink)
  if not equipLoc then return nil end
  return equipLoc, itemType, itemSubType
end

-- Resolve an entry to its item link (loading from itemID when needed).
function FF.StatScan.GetEntryLink(entry, callback)
  ResolveLink(entry, callback)
end

-- Read tooltip text for a link, loading the item first if it isn't cached yet.
function FF.StatScan.ReadItemTextAsync(link, callback)
  if not link then callback(nil); return end
  local text = FF.StatScan.ReadItemText(link)
  if text then callback(text); return end
  local id = ItemIDFromLink(link)
  local item = id and Item:CreateFromItemID(id)
  if item and not item:IsItemEmpty() then
    item:ContinueOnItemLoad(function()
      callback(FF.StatScan.ReadItemText(link))
    end)
  else
    callback(nil)
  end
end

function FF.StatScan.GetEntryText(entry, callback)
  FF.StatScan.GetEntryLink(entry, function(link)
    if not link then callback(nil, nil); return end
    FF.StatScan.ReadItemTextAsync(link, function(text)
      callback(text, link)
    end)
  end)
end
