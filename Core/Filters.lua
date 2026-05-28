FF.Filters = {}

local C = FF.Constants
local AHCut = C.AHCutPercent / 100
local Undercut = C.DefaultUndercutPercent / 100
local DepositRate = C.DepositPercent / 100
local HistoricalCap = C.HistoricalMultipleCap
local CallerID = "Auctionator Plus"

function FF.Filters.Commit()
  local panel = FF.panel
  if not panel then return end

  local qtyPct = tonumber(panel.inputs.MaxQtyPct:GetText())
  FF.committedMaxQtyPct = (qtyPct and qtyPct > 0) and qtyPct or 0

  local gold = tonumber(panel.inputs.MaxInvest:GetText())
  FF.committedMaxInvest = (gold and gold > 0) and (gold * 10000) or 0

  local profit = tonumber(panel.inputs.MinProfit:GetText())
  FF.committedMinProfit = (profit and profit > 0) and (profit * 10000) or 0

  local roi = tonumber(panel.inputs.MinROI:GetText())
  FF.committedMinROI = (roi and roi > 0) and (roi / 100) or 0
end

local function GetVendorPrice(itemLink)
  if not itemLink then return 0 end
  local vendor = select(11, GetItemInfo(itemLink))
  return vendor or 0
end

local function GetHistoricalPrice(itemLink)
  if not itemLink then return nil end
  if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then return nil end
  local fetch = Auctionator.API.v1.GetAuctionPriceByItemLink
  if not fetch then return nil end
  local ok, price = pcall(fetch, CallerID, itemLink)
  if ok and type(price) == "number" and price > 0 then return price end
  return nil
end

local function GetAuctionAge(itemLink)
  if not itemLink then return nil end
  if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then return nil end
  local fetch = Auctionator.API.v1.GetAuctionAgeByItemLink
  if not fetch then return nil end
  local ok, age = pcall(fetch, CallerID, itemLink)
  if ok and type(age) == "number" and age >= 0 then return age end
  return nil
end

local function RepostMultiplier(ageDays)
  if not ageDays then return 1 end
  if ageDays <= 1 then return 1 end
  if ageDays <= 3 then return 1.5 end
  if ageDays <= 7 then return 2 end
  return 3
end

local function DBKeyForLink(itemLink)
  if not itemLink then return nil end
  if not (Auctionator and Auctionator.Utilities
      and Auctionator.Utilities.BasicDBKeyFromLink) then
    return nil
  end
  local ok, key = pcall(Auctionator.Utilities.BasicDBKeyFromLink, itemLink)
  if not ok then return nil end
  return key
end

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

function FF.Filters.BuildFlip(scannedRecord)
  local listings = scannedRecord.listings
  if not listings or #listings < 2 then return nil end

  local entry = scannedRecord.entry
  local firstAuction = entry and entry.entries and entry.entries[1]
  local itemLink = (entry and entry.itemLink) or (firstAuction and firstAuction.itemLink)
  local itemName = entry and entry.itemName
  if not itemName and itemLink then
    itemName = GetItemInfo(itemLink)
  end

  local isCommodity = scannedRecord.isCommodity == true
  local vendorPrice = GetVendorPrice(itemLink)
  local baseDeposit = isCommodity and 0 or (vendorPrice * DepositRate)
  local auctionAge = GetAuctionAge(itemLink)
  local repostMult = RepostMultiplier(auctionAge)
  local depositPerUnit = baseDeposit * repostMult
  local historicalPrice = GetHistoricalPrice(itemLink)

  local best = FF.Bracket.FindBest(listings, {
    cut = AHCut,
    undercut = Undercut,
    depositPerUnit = depositPerUnit,
    vendorPrice = vendorPrice,
    historicalPrice = historicalPrice,
    maxHistoricalMultiple = HistoricalCap,
  })
  if not best then return nil end

  if best.roi < FF.committedMinROI then return nil end
  if FF.committedMaxInvest > 0 and best.totalCost > FF.committedMaxInvest then return nil end
  if FF.committedMinProfit > 0 and best.margin < FF.committedMinProfit then return nil end

  local displayQuantity = (entry and entry.totalQuantity) or 0
  local relativeQuantity = (displayQuantity > 0) and (best.totalQuantity / displayQuantity * 100) or 0
  if FF.committedMaxQtyPct > 0 and relativeQuantity > FF.committedMaxQtyPct then return nil end

  local stats = DBKeyForLink(itemLink)
  stats = stats and FF.History.Compute(stats) or nil

  local underpriced
  if stats and stats.averageMinBuyout and stats.averageMinBuyout > 0 then
    local currentMin = listings[1] and listings[1].unitPrice
    if currentMin then
      underpriced = (currentMin - stats.averageMinBuyout) / stats.averageMinBuyout * 100
    end
  end

  return {
    entry = entry,
    itemKey = entry and entry.itemKey,
    itemLink = itemLink,
    itemName = itemName,
    topPrice = best.topPrice,
    sellPrice = best.sellPrice,
    margin = best.margin,
    totalCost = best.totalCost,
    totalQuantity = best.totalQuantity,
    displayQuantity = displayQuantity,
    relativeQuantity = relativeQuantity,
    depositCost = best.depositCost,
    roi = best.roi,
    isCommodity = isCommodity,
    auctionAge = auctionAge,
    repostMultiplier = repostMult,
    underpriced = underpriced,
    volatility = stats and stats.volatility,
    volatilityBucket = stats and stats.volatilityBucket,
    sellers = CountSellers(listings, best.bracketEnd + 1),
  }
end

function FF.Filters.RebuildAll()
  FF.Filters.Commit()
  FF.flips = {}
  for _, record in ipairs(FF.scanned) do
    local flip = FF.Filters.BuildFlip(record)
    if flip then
      table.insert(FF.flips, flip)
    end
  end
  if FF.panel then FF.panel:Render() end
end

function FF.Filters.SortFlips(flips)
  local prop = FF.sortProperty or "roi"
  local asc = (FF.sortDirection or "desc") == "asc"
  table.sort(flips, function(a, b)
    local av, bv
    if prop == "itemName" then
      av = FF.Format.StripItemColor(a.itemName or a.itemLink)
      bv = FF.Format.StripItemColor(b.itemName or b.itemLink)
    else
      av = a[prop] or 0
      bv = b[prop] or 0
    end
    if asc then return av < bv end
    return av > bv
  end)
end
