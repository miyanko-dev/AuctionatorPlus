FF.Adapter = {}

local cachedResults = {}
local resultsByKey = {}

function FF.Adapter.KeyForEntry(entry)
  return entry.itemString or tostring(entry.itemLink)
end

local function CollectListingsFromResult(result)
  local listings = {}
  local player = (GetUnitName("player"))
  if not result or not result.entries then return listings end

  for _, auction in ipairs(result.entries) do
    local info = auction.info
    if info then
      local buyout = info[Auctionator.Constants.AuctionItemInfo.Buyout] or 0
      local quantity = info[Auctionator.Constants.AuctionItemInfo.Quantity] or 0
      local owner = info[Auctionator.Constants.AuctionItemInfo.Owner]
      if buyout > 0 and quantity > 0 and owner ~= player then
        table.insert(listings, {
          unitPrice = buyout / quantity,
          cost = buyout,
          quantity = quantity,
        })
      end
    end
  end
  return listings
end

local function StoreResults(entries)
  if type(entries) ~= "table" then return end
  for _, result in ipairs(entries) do
    if result and result.entries then
      local key = FF.Adapter.KeyForEntry(result)
      resultsByKey[key] = result
      table.insert(cachedResults, result)
    end
  end
end

function FF.Adapter.ScanEntries(entries, onListings, onComplete)
  for _, entry in ipairs(entries) do
    local key = FF.Adapter.KeyForEntry(entry)
    local result = resultsByKey[key] or entry
    local listings = CollectListingsFromResult(result)
    onListings(entry, listings)
  end
  onComplete()
end

function FF.Adapter.AbortScan()
end

function FF.Adapter.OpenFlipDetails(flip)
  if not flip or not flip.entry then return end
  local key = FF.Adapter.KeyForEntry(flip.entry)
  local result = resultsByKey[key] or flip.entry
  if not result or not result.entries then return end

  if Auctionator and Auctionator.EventBus and Auctionator.Buying then
    Auctionator.EventBus
      :RegisterSource(FF.Adapter._busReceiver, "FlipperClassicOpenDetails")
      :Fire(FF.Adapter._busReceiver, Auctionator.Buying.Events.ShowForShopping, result)
      :Fire(FF.Adapter._busReceiver, Auctionator.Shopping.Tab.Events.BuyScreenShown)
      :UnregisterSource(FF.Adapter._busReceiver)
  end

  if FF.panel and FF.panel:IsShown() then
    FF.panel:Hide()
  end
end

function FF.Adapter.GetAuctionHouseFrame()
  return AuctionFrame
end

function FF.Adapter.GetAnchorButton()
  return AuctionatorShoppingFrame and AuctionatorShoppingFrame.ExportCSV or nil
end

function FF.Adapter.CreateDropdown(parent, width, options, getKey, setKey)
  local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(dd, width)
  UIDropDownMenu_SetText(dd, FF.Format.LabelForKey(options, getKey()))
  UIDropDownMenu_Initialize(dd, function()
    for _, opt in ipairs(options) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = opt.label
      info.checked = (getKey() == opt.key)
      info.func = function()
        setKey(opt.key)
        UIDropDownMenu_SetText(dd, opt.label)
        CloseDropDownMenus()
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  return dd
end

local function ReceiveEvent(_, eventName, eventData)
  if eventName == Auctionator.Shopping.Tab.Events.SearchStart then
    cachedResults = {}
    resultsByKey = {}
    FF.Scanner.ResetCollected()
  elseif eventName == Auctionator.Shopping.Tab.Events.SearchIncrementalUpdate then
    StoreResults(eventData)
    FF.Scanner.CollectEntries(eventData)
  elseif eventName == Auctionator.Shopping.Tab.Events.SearchEnd then
    StoreResults(eventData)
    FF.Scanner.CollectEntries(eventData)
  elseif eventName == Auctionator.Shopping.Tab.Events.BuyScreenShown then
    if FF.panel and FF.panel:IsShown() then FF.panel:Hide() end
  end
end

FF.Adapter._busReceiver = { ReceiveEvent = ReceiveEvent }

function FF.Adapter.RegisterEventBus()
  if FF.Adapter._busRegistered then return end
  if not (Auctionator and Auctionator.EventBus and Auctionator.Shopping
      and Auctionator.Shopping.Tab and Auctionator.Buying) then
    return
  end
  FF.Adapter._busRegistered = true

  Auctionator.EventBus:RegisterSource(FF.Adapter._busReceiver, "FlipperClassicAdapter")
  Auctionator.EventBus:Register(FF.Adapter._busReceiver, {
    Auctionator.Shopping.Tab.Events.SearchStart,
    Auctionator.Shopping.Tab.Events.SearchEnd,
    Auctionator.Shopping.Tab.Events.SearchIncrementalUpdate,
    Auctionator.Shopping.Tab.Events.BuyScreenShown,
  })
end
