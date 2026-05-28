FF.StatFilter = {
  running = false,
  totalToScan = 0,
  scannedCount = 0,
  generation = 0,
}

local CallerID = "Auctionator Plus"

local aliasCache
local function BuildAliases()
  local aliases = {}
  local function add(key, value)
    if type(value) ~= "string" or value == "" then return end
    aliases[key:lower()] = value:lower()
  end
  add("agi",       _G.ITEM_MOD_AGILITY_SHORT)
  add("agility",   _G.ITEM_MOD_AGILITY_SHORT)
  add("str",       _G.ITEM_MOD_STRENGTH_SHORT)
  add("strength",  _G.ITEM_MOD_STRENGTH_SHORT)
  add("sta",       _G.ITEM_MOD_STAMINA_SHORT)
  add("stamina",   _G.ITEM_MOD_STAMINA_SHORT)
  add("int",       _G.ITEM_MOD_INTELLECT_SHORT)
  add("intellect", _G.ITEM_MOD_INTELLECT_SHORT)
  add("spi",       _G.ITEM_MOD_SPIRIT_SHORT)
  add("spirit",    _G.ITEM_MOD_SPIRIT_SHORT)

  local dpsTemplate = _G.DPS_TEMPLATE
  if type(dpsTemplate) == "string" then
    local phrase = strtrim((dpsTemplate:gsub("%%s", "")))
    if phrase ~= "" then add("dps", phrase:lower()) end
  end
  return aliases
end

local function Aliases()
  if not aliasCache then aliasCache = BuildAliases() end
  return aliasCache
end

function FF.StatFilter.ParseQuery(input)
  if type(input) ~= "string" then return {} end
  local aliases = Aliases()
  local tokens = {}
  for raw in input:gmatch("[^,]+") do
    local token = strtrim(raw):lower()
    if token ~= "" then
      table.insert(tokens, aliases[token] or token)
    end
  end
  return tokens
end

function FF.StatFilter.Matches(text, tokens)
  if type(text) ~= "string" or not tokens or #tokens == 0 then return false end
  for _, token in ipairs(tokens) do
    if not text:find(token, 1, true) then return false end
  end
  return true
end

function FF.StatFilter.ResetResults()
  FF.statMatches = {}
  FF.StatFilter.scannedCount = 0
  FF.StatFilter.totalToScan = 0
  if FF.statPanel then
    FF.statPanel:SetRunningUI(false)
    FF.statPanel:Render()
  end
end

function FF.StatFilter.Abort()
  if not FF.StatFilter.running then return end
  FF.StatFilter.running = false
  FF.StatFilter.generation = FF.StatFilter.generation + 1
  if FF.statPanel then FF.statPanel:SetRunningUI(false) end
end

local function DBKeyForLink(itemLink)
  if not (Auctionator and Auctionator.Utilities
      and Auctionator.Utilities.BasicDBKeyFromLink) then
    return nil
  end
  local ok, key = pcall(Auctionator.Utilities.BasicDBKeyFromLink, itemLink)
  if not ok then return nil end
  return key
end

local function CurrentBuyout(itemLink)
  if not (Auctionator and Auctionator.API and Auctionator.API.v1
      and Auctionator.API.v1.GetAuctionPriceByItemLink) then
    return nil
  end
  local ok, price = pcall(
    Auctionator.API.v1.GetAuctionPriceByItemLink,
    CallerID,
    itemLink
  )
  if not ok then return nil end
  if type(price) ~= "number" or price <= 0 then return nil end
  return price
end

local function BuildMatchMetrics(itemLink)
  local buyout = CurrentBuyout(itemLink)
  local dbKey = DBKeyForLink(itemLink)
  local stats = dbKey and FF.History.Compute(dbKey) or nil
  local avg = stats and stats.averageMinBuyout or nil
  local trend
  if buyout and avg and avg > 0 then
    trend = (buyout - avg) / avg * 100
  end
  return buyout, avg, trend
end

local function recordMatch(entry, itemLink, itemText, tokens)
  if not FF.StatFilter.Matches(itemText, tokens) then return end
  local buyout, avg, trend = BuildMatchMetrics(itemLink)
  table.insert(FF.statMatches, {
    entry    = entry,
    itemLink = itemLink,
    itemText = itemText,
    buyout   = buyout,
    avg      = avg,
    trend    = trend,
  })
  if FF.statPanel then FF.statPanel:Render() end
end

function FF.StatFilter.Run(query)
  if not FF.StatScan then return end
  local tokens = FF.StatFilter.ParseQuery(query)
  if #tokens == 0 then
    if FF.statPanel then FF.statPanel:ShowNotice("Enter at least one stat term") end
    return
  end

  FF.StatFilter.Abort()
  FF.statMatches = {}
  FF.StatFilter.scannedCount = 0
  FF.StatFilter.totalToScan = #FF.collected
  FF.StatFilter.running = true
  FF.StatFilter.generation = FF.StatFilter.generation + 1
  local gen = FF.StatFilter.generation

  if FF.statPanel then
    FF.statPanel:ClearNotice()
    FF.statPanel:SetRunningUI(true)
    FF.statPanel:Render()
  end

  if FF.StatFilter.totalToScan == 0 then
    FF.StatFilter.running = false
    if FF.statPanel then
      FF.statPanel:SetRunningUI(false)
      FF.statPanel:Render()
    end
    return
  end

  for _, entry in ipairs(FF.collected) do
    FF.StatScan.GetEntryText(entry, function(itemText, itemLink)
      if gen ~= FF.StatFilter.generation then return end
      if itemText and itemLink then
        recordMatch(entry, itemLink, itemText, tokens)
      end
      FF.StatFilter.scannedCount = FF.StatFilter.scannedCount + 1
      if FF.StatFilter.scannedCount >= FF.StatFilter.totalToScan then
        FF.StatFilter.running = false
        if FF.statPanel then
          FF.statPanel:SetRunningUI(false)
          FF.statPanel:Render()
        end
      end
    end)
  end
end
