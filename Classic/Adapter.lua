FF.Adapter = {}

local resultsByKey = {}

function FF.Adapter.KeyForEntry(entry)
  return entry.itemString or tostring(entry.itemLink)
end

local function CollectListings(result)
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
      resultsByKey[FF.Adapter.KeyForEntry(result)] = result
    end
  end
end

function FF.Adapter.ScanEntries(entries, onListings, onComplete)
  for _, entry in ipairs(entries) do
    local key = FF.Adapter.KeyForEntry(entry)
    local result = resultsByKey[key] or entry
    onListings(entry, CollectListings(result))
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
      :RegisterSource(FF.Adapter._busReceiver, "AuctionatorPlusOpenDetails")
      :Fire(FF.Adapter._busReceiver, Auctionator.Buying.Events.ShowForShopping, result)
      :Fire(FF.Adapter._busReceiver, Auctionator.Shopping.Tab.Events.BuyScreenShown)
      :UnregisterSource(FF.Adapter._busReceiver)
  end

  if FF.panel and FF.panel:IsShown() then
    FF.panel:Hide()
  end
end

function FF.Adapter.GetAHFrame()
  return AuctionFrame
end

function FF.Adapter.IsAHVisible()
  return AuctionFrame ~= nil and AuctionFrame:IsShown()
end

local function IsDetailFrame(name)
  if type(name) ~= "string" then return false end
  if name:match("^Auctionator.*Sell") then return true end
  if name:match("^Auctionator.*SaleItem") then return true end
  if name:match("^Auctionator.*Buy") then return true end
  return false
end

function FF.Adapter.ShouldSuppressTooltip(tooltip)
  if not tooltip or not tooltip.GetOwner then return false end
  local owner = tooltip:GetOwner()
  if not owner then return false end

  local node = owner
  while node do
    local name = node.GetName and node:GetName()
    if name == "AuctionFrameAuctions"
        and node.IsShown and node:IsShown() then
      return true
    end
    if IsDetailFrame(name)
        and node.IsShown and node:IsShown() then
      return true
    end
    node = node.GetParent and node:GetParent() or nil
  end
  return false
end

function FF.Adapter.RegisterTooltipHook(apply)
  if FF.Adapter._tooltipHooked then return end
  if type(apply) ~= "function" then return end

  local function dispatch(tooltip)
    if not tooltip or not tooltip.GetItem then return end
    local _, link = tooltip:GetItem()
    if not link or link == "" then return end
    pcall(apply, tooltip, link)
  end

  if GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", dispatch)
  end
  if ItemRefTooltip and ItemRefTooltip.HookScript then
    ItemRefTooltip:HookScript("OnTooltipSetItem", dispatch)
  end
  FF.Adapter._tooltipHooked = true
end

function FF.Adapter.GetAnchorButton()
  return AuctionatorShoppingFrame and AuctionatorShoppingFrame.ExportCSV or nil
end

function FF.Adapter.CreateDropdown(parent, width, options, getKey, setKey)
  local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle2DropdownTemplate")
  dd:SetWidth(width)
  dd:SetDefaultText(FF.Format.LabelForKey(options, getKey()))
  dd:SetupMenu(function(_, root)
    for _, opt in ipairs(options) do
      root:CreateRadio(
        opt.label,
        function() return getKey() == opt.key end,
        function() setKey(opt.key) end)
    end
  end)
  return dd
end

local function ReceiveEvent(_, eventName, eventData)
  if eventName == Auctionator.Shopping.Tab.Events.SearchStart then
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

  Auctionator.EventBus:RegisterSource(FF.Adapter._busReceiver, "AuctionatorPlusClassic")
  Auctionator.EventBus:Register(FF.Adapter._busReceiver, {
    Auctionator.Shopping.Tab.Events.SearchStart,
    Auctionator.Shopping.Tab.Events.SearchEnd,
    Auctionator.Shopping.Tab.Events.SearchIncrementalUpdate,
    Auctionator.Shopping.Tab.Events.BuyScreenShown,
  })
end
