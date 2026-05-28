FF.Adapter = {}

local SCAN_TIMEOUT_SECONDS = FF.Constants.ScanTimeoutSeconds

local scanState = {
  queue = {},
  currentEntry = nil,
  currentKey = nil,
  currentIsCommodity = nil,
  currentTimeout = nil,
  active = false,
  onListings = nil,
  onComplete = nil,
}

local function KeyString(itemKey)
  return Auctionator.Utilities.ItemKeyString(itemKey)
end

function FF.Adapter.KeyForEntry(entry)
  return KeyString(entry.itemKey)
end

local function CollectCommodityListings(itemID)
  local listings = {}
  local total = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
  for index = 1, total do
    local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
    if info and info.unitPrice and info.unitPrice > 0 then
      local quantity = info.quantity or 1
      if quantity < 1 then quantity = 1 end
      table.insert(listings, {
        unitPrice = info.unitPrice,
        cost = info.unitPrice * quantity,
        quantity = quantity,
      })
    end
  end
  return listings
end

local function CollectItemListings(itemKey)
  local listings = {}
  local total = C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0
  for index = 1, total do
    local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
    if info and info.buyoutAmount and info.buyoutAmount > 0 then
      local quantity = info.quantity or 1
      if quantity < 1 then quantity = 1 end
      table.insert(listings, {
        unitPrice = info.buyoutAmount / quantity,
        cost = info.buyoutAmount,
        quantity = quantity,
      })
    end
  end
  return listings
end

local function ScanNext()
  if not scanState.active then return end
  if scanState.currentTimeout then
    scanState.currentTimeout:Cancel()
    scanState.currentTimeout = nil
  end

  if #scanState.queue == 0 then
    scanState.active = false
    scanState.currentEntry = nil
    scanState.currentKey = nil
    scanState.currentIsCommodity = nil
    if scanState.onComplete then scanState.onComplete() end
    return
  end

  local entry = table.remove(scanState.queue, 1)
  scanState.currentEntry = entry
  scanState.currentKey = KeyString(entry.itemKey)
  scanState.currentIsCommodity = nil

  local myKey = scanState.currentKey
  Auctionator.AH.GetItemKeyInfo(entry.itemKey, function(itemKeyInfo)
    if not scanState.active or scanState.currentKey ~= myKey then return end
    if not itemKeyInfo then
      if scanState.onListings then scanState.onListings(entry, nil) end
      ScanNext()
      return
    end

    scanState.currentIsCommodity = itemKeyInfo.isCommodity == true

    local expectedKey = scanState.currentKey
    scanState.currentTimeout = C_Timer.NewTimer(SCAN_TIMEOUT_SECONDS, function()
      if scanState.currentKey == expectedKey then
        if scanState.onListings then scanState.onListings(entry, nil) end
        ScanNext()
      end
    end)

    if scanState.currentIsCommodity then
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
  end)
end

local function HandleScanResult(itemKeyOrID)
  if not scanState.active or not scanState.currentEntry then return end

  local expectedKey = scanState.currentEntry.itemKey
  local matches = false
  if type(itemKeyOrID) == "number" then
    matches = expectedKey.itemID == itemKeyOrID
  elseif type(itemKeyOrID) == "table" then
    matches = KeyString(itemKeyOrID) == scanState.currentKey
  end
  if not matches then return end

  local listings
  if scanState.currentIsCommodity then
    listings = CollectCommodityListings(expectedKey.itemID)
  else
    listings = CollectItemListings(expectedKey)
  end

  if scanState.onListings then
    scanState.onListings(scanState.currentEntry, listings, scanState.currentIsCommodity)
  end

  ScanNext()
end

function FF.Adapter.ScanEntries(entries, onListings, onComplete)
  scanState.queue = {}
  for _, entry in ipairs(entries) do
    table.insert(scanState.queue, entry)
  end
  scanState.onListings = onListings
  scanState.onComplete = onComplete
  scanState.active = true
  ScanNext()
end

function FF.Adapter.AbortScan()
  if scanState.currentTimeout then
    scanState.currentTimeout:Cancel()
    scanState.currentTimeout = nil
  end
  scanState.active = false
  scanState.queue = {}
  scanState.currentEntry = nil
  scanState.currentKey = nil
  scanState.currentIsCommodity = nil
end

function FF.Adapter.OpenFlipDetails(flip)
  local term
  if flip.itemLink then
    local name = GetItemInfo(flip.itemLink)
    if name and name ~= "" then term = name end
  end
  if not term or term == "" then term = flip.itemName end
  term = FF.Format.SanitizeSearchTerm(term)
  if not term then return end

  local ok = pcall(Auctionator.API.v1.MultiSearchExact, "Auctionator Plus", { term })
  if not ok then
    pcall(Auctionator.API.v1.MultiSearch, "Auctionator Plus", { term })
  end
end

function FF.Adapter.GetAHFrame()
  return AuctionHouseFrame
end

function FF.Adapter.RegisterTooltipHook(apply)
  if FF.Adapter._tooltipHooked then return end
  if type(apply) ~= "function" then return end
  if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
      and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item) then
    return
  end
  FF.Adapter._tooltipHooked = true

  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, tipData)
    local link = tipData and tipData.hyperlink
    if (not link or link == "") and tipData and tipData.id and C_Item and C_Item.GetItemInfo then
      link = select(2, C_Item.GetItemInfo(tipData.id))
    end
    if (not link or link == "") and TooltipUtil and TooltipUtil.GetDisplayedItem then
      local _name, displayedLink = TooltipUtil.GetDisplayedItem(tooltip)
      link = displayedLink
    end
    if not link or link == "" then return end
    pcall(apply, tooltip, link)
  end)
end

function FF.Adapter.CreateDropdown(parent, width, options, getKey, setKey)
  local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  dd:SetSize(width, 24)
  dd:SetDefaultText(FF.Format.LabelForKey(options, getKey()))
  dd:SetupMenu(function(_, rootDescription)
    for _, opt in ipairs(options) do
      rootDescription:CreateRadio(
        opt.label,
        function() return getKey() == opt.key end,
        function() setKey(opt.key) end
      )
    end
  end)
  return dd
end

local function ReceiveEvent(_, eventName, eventData, ...)
  if eventName == Auctionator.Shopping.Tab.Events.SearchStart then
    FF.Scanner.ResetCollected()
  elseif eventName == Auctionator.Shopping.Tab.Events.SearchIncrementalUpdate then
    FF.Scanner.CollectEntries(eventData)
  elseif eventName == Auctionator.Shopping.Tab.Events.SearchEnd then
    FF.Scanner.CollectEntries(eventData)
  elseif eventName == Auctionator.Buying.Events.ShowCommodityBuy
      or eventName == Auctionator.Buying.Events.ShowItemBuy then
    FF.Scanner.Abort()
  elseif eventName == Auctionator.AH.Events.CommoditySearchResultsReady then
    if scanState.currentIsCommodity == true then HandleScanResult(eventData) end
  elseif eventName == Auctionator.AH.Events.ItemSearchResultsReady then
    if scanState.currentIsCommodity == false then HandleScanResult(eventData) end
  end
end

FF.Adapter._busReceiver = { ReceiveEvent = ReceiveEvent }

function FF.Adapter.RegisterEventBus()
  if FF.Adapter._busRegistered then return end
  if not (Auctionator and Auctionator.EventBus and Auctionator.AH and Auctionator.AH.Events
      and Auctionator.Shopping and Auctionator.Shopping.Tab and Auctionator.Buying) then
    return
  end
  FF.Adapter._busRegistered = true

  Auctionator.EventBus:RegisterSource(FF.Adapter._busReceiver, "AuctionatorPlusRetail")
  Auctionator.EventBus:Register(FF.Adapter._busReceiver, {
    Auctionator.Shopping.Tab.Events.SearchStart,
    Auctionator.Shopping.Tab.Events.SearchEnd,
    Auctionator.Shopping.Tab.Events.SearchIncrementalUpdate,
    Auctionator.Buying.Events.ShowCommodityBuy,
    Auctionator.Buying.Events.ShowItemBuy,
    Auctionator.AH.Events.CommoditySearchResultsReady,
    Auctionator.AH.Events.ItemSearchResultsReady,
  })
end
