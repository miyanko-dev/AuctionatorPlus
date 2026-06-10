local _, AP = ...

AP.Arbitrage = {
  scanning = false,
}

local C = AP.Constants
local AHCut = C.AHCutPercent / 100
local Undercut = C.DefaultUndercutPercent / 100
local DepositRate = C.DepositPercent / 100
local HistoricalCap = C.HistoricalMultipleCap
local RATIO_FLOOR = 1 + C.MinGapPercent / 100

-- ===== Shopping-search capture =====

-- Full search results by item key, kept so a scan can read every listing of an
-- entry and a row click can reopen its buy view.
local resultsByKey = {}

local function KeyForEntry(entry)
  return entry.itemString or tostring(entry.itemLink)
end

local function StoreResults(entries)
  if type(entries) ~= "table" then return end
  for _, result in ipairs(entries) do
    if result and result.entries then
      resultsByKey[KeyForEntry(result)] = result
    end
  end
end

local function CollectEntries(entries)
  if type(entries) ~= "table" then return end
  for _, entry in ipairs(entries) do
    if entry and entry.totalQuantity and entry.totalQuantity > 0 then
      local key = KeyForEntry(entry)
      if key and not AP.seenKeys[key] then
        AP.seenKeys[key] = true
        table.insert(AP.collected, entry)
      end
    end
  end
end

local function ResetCollected()
  AP.collected = {}
  AP.seenKeys = {}
  AP.scanned = {}
  AP.flips = {}
  AP.hasScanned = false
  AP.Arbitrage.scanning = false
  if AP.panel then
    AP.panel:SetScanningUI(false)
    AP.panel:Render()
  end
end

-- Buyable third-party listings of a search result, cheapest-relevant fields only.
local function CollectListings(result)
  local listings = {}
  local player = UnitName("player")
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
          owner = owner,
        })
      end
    end
  end
  return listings
end

-- ===== Bracket search =====

-- Best buyout bracket by ROI: sort listings by unit price and consider buying
-- everything below each price gap that clears RATIO_FLOOR, reselling just
-- under the gap's top price.
local function FindBestBracket(listings, depositPerUnit, vendorPrice, historicalPrice)
  local n = #listings
  if n < 2 then return nil end

  table.sort(listings, function(a, b) return a.unitPrice < b.unitPrice end)

  local prefixCost = {}
  local prefixQty = {}
  local runningCost = 0
  local runningQty = 0
  for j = 1, n do
    runningCost = runningCost + listings[j].cost
    runningQty = runningQty + listings[j].quantity
    prefixCost[j] = runningCost
    prefixQty[j] = runningQty
  end

  local best
  local bestROI = 0

  for k = 1, n - 1 do
    local topPrice = listings[k + 1].unitPrice
    local cheapTopPrice = listings[k].unitPrice
    local gapRatio = topPrice / cheapTopPrice

    if gapRatio >= RATIO_FLOOR then
      local sellPrice = topPrice * (1 - Undercut)
      local effectiveSell = sellPrice * (1 - AHCut)

      local okVendor = effectiveSell >= vendorPrice
      local okHistorical = (not historicalPrice) or
        (sellPrice <= historicalPrice * HistoricalCap)

      if okVendor and okHistorical then
        local bracketCost = prefixCost[k]
        local bracketQty = prefixQty[k]
        local revenue = bracketQty * effectiveSell
        local depositCost = bracketQty * depositPerUnit
        local margin = revenue - bracketCost - depositCost
        local roi = bracketCost > 0 and (margin / bracketCost) or 0

        if margin > 0 and roi > bestROI then
          bestROI = roi
          best = {
            bracketEnd = k,
            margin = margin,
            totalCost = bracketCost,
            totalQuantity = bracketQty,
            roi = roi,
          }
        end
      end
    end
  end

  return best
end

-- ===== Flip building and filters =====

-- Read the panel's filter inputs into the committed thresholds.
local function CommitFilters()
  local panel = AP.panel
  if not panel then return end

  local qtyPct = tonumber(panel.inputs.MaxQtyPct:GetText())
  AP.committedMaxQtyPct = (qtyPct and qtyPct > 0) and qtyPct or 0

  local gold = tonumber(panel.inputs.MaxInvest:GetText())
  AP.committedMaxInvest = (gold and gold > 0) and (gold * 10000) or 0

  local profit = tonumber(panel.inputs.MinProfit:GetText())
  AP.committedMinProfit = (profit and profit > 0) and (profit * 10000) or 0

  local roi = tonumber(panel.inputs.MinROI:GetText())
  AP.committedMinROI = (roi and roi > 0) and (roi / 100) or 0
end

local function GetVendorPrice(itemLink)
  if not itemLink then return 0 end
  local vendor = select(11, C_Item.GetItemInfo(itemLink))
  return vendor or 0
end

-- Stale items get relisted more often before selling, multiplying deposit cost.
local function RepostMultiplier(ageDays)
  if not ageDays then return 1 end
  if ageDays <= 1 then return 1 end
  if ageDays <= 3 then return 1.5 end
  if ageDays <= 7 then return 2 end
  return 3
end

-- Distinct competing sellers above the bracket; nil when the scan carried no
-- owner data at all.
local function CountSellers(listings, fromIndex)
  if fromIndex > #listings then return nil end
  local owners = {}
  local count = 0
  local hasAnyOwner = false
  for i = fromIndex, #listings do
    local owner = listings[i].owner
    if owner and owner ~= "" then
      hasAnyOwner = true
      if not owners[owner] then
        owners[owner] = true
        count = count + 1
      end
    end
  end
  if not hasAnyOwner then return nil end
  return count
end

local function BuildFlip(scannedRecord)
  local listings = scannedRecord.listings
  if not listings or #listings < 2 then return nil end

  local entry = scannedRecord.entry
  local firstAuction = entry and entry.entries and entry.entries[1]
  local itemLink = (entry and entry.itemLink) or (firstAuction and firstAuction.itemLink)
  local itemName = entry and entry.itemName
  if not itemName and itemLink then
    itemName = C_Item.GetItemInfo(itemLink)
  end

  local vendorPrice = GetVendorPrice(itemLink)
  local repostMult = RepostMultiplier(AP.Bridge.AuctionAge(itemLink))
  local depositPerUnit = vendorPrice * DepositRate * repostMult
  local historicalPrice = AP.Bridge.AuctionPrice(itemLink)

  local best = FindBestBracket(listings, depositPerUnit, vendorPrice, historicalPrice)
  if not best then return nil end

  if best.roi < AP.committedMinROI then return nil end
  if AP.committedMaxInvest > 0 and best.totalCost > AP.committedMaxInvest then return nil end
  if AP.committedMinProfit > 0 and best.margin < AP.committedMinProfit then return nil end

  local displayQuantity = (entry and entry.totalQuantity) or 0
  local relativeQuantity = (displayQuantity > 0) and (best.totalQuantity / displayQuantity * 100) or 0
  if AP.committedMaxQtyPct > 0 and relativeQuantity > AP.committedMaxQtyPct then return nil end

  local dbKey = AP.Bridge.DBKeyForLink(itemLink)
  local stats = dbKey and AP.History.Compute(dbKey) or nil

  local underpriced
  if stats and stats.averageMinBuyout and stats.averageMinBuyout > 0 then
    local currentMin = listings[1] and listings[1].unitPrice
    if currentMin then
      underpriced = (currentMin - stats.averageMinBuyout) / stats.averageMinBuyout * 100
    end
  end

  return {
    entry = entry,
    itemLink = itemLink,
    itemName = itemName,
    margin = best.margin,
    totalCost = best.totalCost,
    relativeQuantity = relativeQuantity,
    roi = best.roi,
    underpriced = underpriced,
    volatility = stats and stats.volatility,
    volatilityBucket = stats and stats.volatilityBucket,
    sellers = CountSellers(listings, best.bracketEnd + 1),
  }
end

-- Re-derive every flip from the already-scanned records (filter input changed).
function AP.Arbitrage.RebuildAll()
  CommitFilters()
  AP.flips = {}
  for _, record in ipairs(AP.scanned) do
    local flip = BuildFlip(record)
    if flip then
      table.insert(AP.flips, flip)
    end
  end
  if AP.panel then AP.panel:Render() end
end

function AP.Arbitrage.SortFlips(flips)
  local prop = AP.sortProperty or "roi"
  local asc = (AP.sortDirection or "desc") == "asc"
  table.sort(flips, function(a, b)
    local av, bv
    if prop == "itemName" then
      av = AP.Format.StripItemColor(a.itemName or a.itemLink)
      bv = AP.Format.StripItemColor(b.itemName or b.itemLink)
    else
      av = a[prop] or 0
      bv = b[prop] or 0
    end
    if asc then return av < bv end
    return av > bv
  end)
end

-- ===== Scan =====

function AP.Arbitrage.Abort()
  AP.Arbitrage.scanning = false
  if AP.panel then AP.panel:SetScanningUI(false) end
end

function AP.Arbitrage.Start()
  AP.Arbitrage.Abort()
  CommitFilters()

  AP.scanned = {}
  AP.flips = {}

  if #AP.collected == 0 then
    if AP.panel then
      AP.panel:SetScanningUI(false)
      AP.panel:Render()
    end
    return
  end

  AP.Arbitrage.scanning = true
  if AP.panel then
    AP.panel:SetScanningUI(true)
  end

  for _, entry in ipairs(AP.collected) do
    local listings = CollectListings(resultsByKey[KeyForEntry(entry)] or entry)
    if #listings >= 2 then
      local record = { entry = entry, listings = listings }
      table.insert(AP.scanned, record)

      local flip = BuildFlip(record)
      if flip then
        table.insert(AP.flips, flip)
      end
    end
  end

  AP.Arbitrage.scanning = false
  AP.hasScanned = true
  if AP.panel then
    AP.panel:SetScanningUI(false)
    AP.panel:Render()
  end
end

-- Reopen the stored search result in Auctionator's buy view (row click).
local detailsSource = {}

function AP.Arbitrage.OpenFlipDetails(flip)
  if not flip or not flip.entry then return end
  local result = resultsByKey[KeyForEntry(flip.entry)] or flip.entry
  if not result.entries then return end

  Auctionator.EventBus
    :RegisterSource(detailsSource, "AuctionatorPlusOpenDetails")
    :Fire(detailsSource, Auctionator.Buying.Events.ShowForShopping, result)
    :Fire(detailsSource, Auctionator.Shopping.Tab.Events.BuyScreenShown)
    :UnregisterSource(detailsSource)
end

-- ===== Event wiring =====

local ShoppingEvents = Auctionator.Shopping.Tab.Events

AP.Bridge.Listen(
  {
    ShoppingEvents.SearchStart,
    ShoppingEvents.SearchIncrementalUpdate,
    ShoppingEvents.SearchEnd,
  },
  function(_, eventName, eventData)
    if eventName == ShoppingEvents.SearchStart then
      resultsByKey = {}
      ResetCollected()
    else
      StoreResults(eventData)
      CollectEntries(eventData)
    end
  end)
