local ADDON_NAME = ...

local PRICE_JUMP_RATIO = 1.10
local MAX_BRACKETS = 5
local SCAN_TIMEOUT_SECONDS = 6
local CHAT_PREFIX = "|cff33ff99[Arbitrage]|r "

local AF = {}
AF.collected = {}
AF.seenKeys = {}
AF.scanQueue = {}
AF.arbitrageKeys = {}
AF.arbitrageInfo = {}
AF.currentEntry = nil
AF.currentKey = nil
AF.currentIsCommodity = nil
AF.scanning = false

local function KeyString(itemKey)
  return Auctionator.Utilities.ItemKeyString(itemKey)
end

local function FormatGold(copper)
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  return string.format("%dg %ds", g, s)
end

local function Announce(message)
  DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. message)
end

local function ExtractBrackets(prices)
  local seen = {}
  local brackets = {}
  for _, price in ipairs(prices) do
    if price > 0 and not seen[price] then
      seen[price] = true
      table.insert(brackets, price)
    end
  end

  table.sort(brackets)

  for index = #brackets, MAX_BRACKETS + 1, -1 do
    brackets[index] = nil
  end

  return brackets
end

local function HasArbitrage(brackets)
  if #brackets < 2 then
    return false
  end

  local minPrice = brackets[1]
  local maxPrice = brackets[#brackets]

  return minPrice > 0 and (maxPrice / minPrice) >= PRICE_JUMP_RATIO
end

local function CollectCommodityPrices(itemID)
  local prices = {}
  local total = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0

  for index = 1, total do
    local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
    if info and info.unitPrice and info.unitPrice > 0 then
      table.insert(prices, info.unitPrice)
    end
  end

  return prices
end

local function CollectItemPrices(itemKey)
  local prices = {}
  local total = C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0

  for index = 1, total do
    local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
    if info and info.buyoutAmount and info.buyoutAmount > 0 then
      local quantity = info.quantity or 1
      if quantity < 1 then
        quantity = 1
      end
      table.insert(prices, info.buyoutAmount / quantity)
    end
  end

  return prices
end

function AF:ResetState()
  self:AbortScan()
  self.collected = {}
  self.seenKeys = {}
  self.arbitrageKeys = {}
  self.arbitrageInfo = {}
end

function AF:CollectEntries(entries)
  if type(entries) ~= "table" then
    return
  end
  for _, entry in ipairs(entries) do
    if entry and entry.itemKey and entry.totalQuantity and entry.totalQuantity > 0 then
      local key = KeyString(entry.itemKey)
      if not self.seenKeys[key] then
        self.seenKeys[key] = true
        table.insert(self.collected, entry)
      end
    end
  end
end

function AF:AbortScan()
  if self.currentTimeout then
    self.currentTimeout:Cancel()
    self.currentTimeout = nil
  end
  self.scanning = false
  self.currentEntry = nil
  self.currentKey = nil
  self.currentIsCommodity = nil
  self.scanQueue = {}
end

function AF:StartScan()
  self:AbortScan()

  for _, entry in ipairs(self.collected) do
    table.insert(self.scanQueue, entry)
  end

  if #self.scanQueue == 0 then
    return
  end

  self.scanning = true
  self:ScanNext()
end

function AF:ScanNext()
  if not self.scanning then
    return
  end

  if self.currentTimeout then
    self.currentTimeout:Cancel()
    self.currentTimeout = nil
  end

  if #self.scanQueue == 0 then
    self.scanning = false
    self.currentEntry = nil
    self.currentKey = nil
    self.currentIsCommodity = nil
    return
  end

  local entry = table.remove(self.scanQueue, 1)
  self.currentEntry = entry
  self.currentKey = KeyString(entry.itemKey)
  self.currentIsCommodity = nil

  local myKey = self.currentKey
  Auctionator.AH.GetItemKeyInfo(entry.itemKey, function(itemKeyInfo)
    if not self.scanning or self.currentKey ~= myKey then
      return
    end

    if not itemKeyInfo then
      self:ScanNext()
      return
    end

    self.currentIsCommodity = itemKeyInfo.isCommodity == true
    self:FireQuery()
  end)
end

function AF:FireQuery()
  if not self.scanning or not self.currentEntry then
    return
  end

  local entry = self.currentEntry
  local expectedKey = self.currentKey

  self.currentTimeout = C_Timer.NewTimer(SCAN_TIMEOUT_SECONDS, function()
    if self.currentKey == expectedKey then
      self:ScanNext()
    end
  end)

  if self.currentIsCommodity then
    Auctionator.AH.SendSearchQueryByItemKey(
      entry.itemKey,
      Auctionator.Constants.CommodityResultsSorts,
      false
    )
  else
    Auctionator.AH.SendSearchQueryByItemKey(
      entry.itemKey,
      { Auctionator.Constants.ItemResultsSorts },
      true
    )
  end
end

function AF:HandleScanResult(itemKeyOrID)
  if not self.scanning or not self.currentEntry then
    return
  end

  local expectedKey = self.currentEntry.itemKey
  local matches = false

  if type(itemKeyOrID) == "number" then
    matches = expectedKey.itemID == itemKeyOrID
  elseif type(itemKeyOrID) == "table" then
    matches = KeyString(itemKeyOrID) == self.currentKey
  end

  if not matches then
    return
  end

  local prices
  if self.currentIsCommodity then
    prices = CollectCommodityPrices(expectedKey.itemID)
  else
    prices = CollectItemPrices(expectedKey)
  end

  local brackets = ExtractBrackets(prices)
  if HasArbitrage(brackets) then
    self.arbitrageKeys[self.currentKey] = true
    self.arbitrageInfo[self.currentKey] = {
      itemName = self.currentEntry.itemName,
      itemLink = self.currentEntry.itemLink,
      minPrice = brackets[1],
      maxPrice = brackets[#brackets],
      brackets = #brackets,
    }

    local name = self.currentEntry.itemLink or self.currentEntry.itemName or "?"
    local ratio = brackets[#brackets] / brackets[1]
    Announce(string.format(
      "Deal found: %s  (%s -> %s, x%.2f across %d brackets)",
      name, FormatGold(brackets[1]), FormatGold(brackets[#brackets]), ratio, #brackets
    ))
  end

  self:ScanNext()
end

function AF:ReceiveEvent(eventName, eventData, ...)
  if eventName == Auctionator.Shopping.Tab.Events.SearchStart then
    self:ResetState()

  elseif eventName == Auctionator.Shopping.Tab.Events.SearchIncrementalUpdate then
    self:CollectEntries(eventData)

  elseif eventName == Auctionator.Shopping.Tab.Events.SearchEnd then
    self:CollectEntries(eventData)
    self:StartScan()

  elseif eventName == Auctionator.Buying.Events.ShowCommodityBuy
      or eventName == Auctionator.Buying.Events.ShowItemBuy then
    self:AbortScan()

  elseif eventName == Auctionator.AH.Events.CommoditySearchResultsReady then
    if self.currentIsCommodity == true then
      self:HandleScanResult(eventData)
    end

  elseif eventName == Auctionator.AH.Events.ItemSearchResultsReady then
    if self.currentIsCommodity == false then
      self:HandleScanResult(eventData)
    end
  end
end

local function RegisterEventBus()
  if AF.registered then
    return
  end
  if not (Auctionator and Auctionator.EventBus and Auctionator.AH and Auctionator.AH.Events
      and Auctionator.Shopping and Auctionator.Shopping.Tab and Auctionator.Buying) then
    return
  end
  AF.registered = true

  Auctionator.EventBus:RegisterSource(AF, "AuctionatorArbitrageFinder")
  Auctionator.EventBus:Register(AF, {
    Auctionator.Shopping.Tab.Events.SearchStart,
    Auctionator.Shopping.Tab.Events.SearchEnd,
    Auctionator.Shopping.Tab.Events.SearchIncrementalUpdate,
    Auctionator.Buying.Events.ShowCommodityBuy,
    Auctionator.Buying.Events.ShowItemBuy,
    Auctionator.AH.Events.CommoditySearchResultsReady,
    Auctionator.AH.Events.ItemSearchResultsReady,
  })
end

local function RegisterSlashCommand()
  SLASH_CAF1 = "/caf"
  SlashCmdList["CAF"] = function(msg)
    local arg = (msg or ""):lower():match("^%s*(%S*)")

    if arg == "list" then
      local count = 0
      for key, info in pairs(AF.arbitrageInfo) do
        count = count + 1
        local name = info.itemLink or info.itemName or key
        local ratio = info.maxPrice / info.minPrice
        Announce(string.format(
          "%s  %s -> %s  x%.2f",
          name, FormatGold(info.minPrice), FormatGold(info.maxPrice), ratio
        ))
      end
      if count == 0 then
        Announce("No deals found yet.")
      end

    elseif arg == "rescan" then
      if #AF.collected == 0 then
        Announce("No shopping entries cached. Run a shopping list search first.")
      else
        Announce(string.format("Rescanning %d item(s)...", #AF.collected))
        AF:StartScan()
      end

    else
      Announce(string.format(
        "registered=%s, scanning=%s, collected=%d, arbitrage=%d",
        tostring(AF.registered), tostring(AF.scanning),
        #AF.collected, (function() local n = 0 for _ in pairs(AF.arbitrageKeys) do n = n + 1 end return n end)()
      ))
      Announce("Commands: /caf list, /caf rescan")
    end
  end
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:RegisterEvent("AUCTION_HOUSE_SHOW")
bootstrap:RegisterEvent("AUCTION_HOUSE_CLOSED")
bootstrap:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    RegisterEventBus()
    RegisterSlashCommand()

  elseif event == "AUCTION_HOUSE_SHOW" then
    RegisterEventBus()

  elseif event == "AUCTION_HOUSE_CLOSED" then
    AF:AbortScan()
  end
end)
