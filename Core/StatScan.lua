FF.StatScan = {}

local SCAN_TIP_NAME = "FFStatScanTooltip"
local scanTip

local function EnsureScanTooltip()
  if scanTip then return scanTip end
  scanTip = CreateFrame("GameTooltip", SCAN_TIP_NAME, nil, "GameTooltipTemplate")
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  return scanTip
end

local function ReadFromTooltipInfo(itemLink)
  if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil end
  local data = C_TooltipInfo.GetHyperlink(itemLink)
  if not data or not data.lines or #data.lines == 0 then return nil end
  local parts = {}
  for _, line in ipairs(data.lines) do
    local left = line.leftText
    local right = line.rightText
    if type(left) == "string" and left ~= "" then table.insert(parts, left) end
    if type(right) == "string" and right ~= "" then table.insert(parts, right) end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, "\n"):lower()
end

local function ReadFromScanTooltip(itemLink)
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
  local text = ReadFromTooltipInfo(itemLink)
  if text and text:find("%S") then return text end
  return ReadFromScanTooltip(itemLink)
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

function FF.StatScan.GetEntryText(entry, callback)
  ResolveLink(entry, function(link)
    if not link then callback(nil, nil); return end
    local text = FF.StatScan.ReadItemText(link)
    if text then callback(text, link); return end
    local id = ItemIDFromLink(link)
    local item = id and Item:CreateFromItemID(id)
    if item and not item:IsItemEmpty() then
      item:ContinueOnItemLoad(function()
        callback(FF.StatScan.ReadItemText(link), link)
      end)
    else
      callback(nil, link)
    end
  end)
end
