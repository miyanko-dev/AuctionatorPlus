FF.Filters = {}

local C = FF.Constants
local AHCut = C.AHCutPercent / 100
local Undercut = C.DefaultUndercutPercent / 100
local DepositRate = C.DepositPercent / 100
local HistoricalCap = C.HistoricalMultipleCap

function FF.Filters.Commit()
  local panel = FF.panel
  if not panel then return end

  local qtyPct = tonumber(panel.MaxQtyPctEditBox:GetText())
  FF.committedMaxQtyPct = (qtyPct and qtyPct > 0) and qtyPct or 0

  local depth = tonumber(panel.MinDepthEditBox:GetText())
  FF.committedMinDepth = (depth and depth > 0) and depth or 0

  local gold = tonumber(panel.MaxInvestEditBox:GetText())
  FF.committedMaxInvest = (gold and gold > 0) and (gold * 10000) or 0

  local roi = tonumber(panel.MinROIEditBox:GetText())
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
  local ok, price = pcall(fetch, "FlipFinder", itemLink)
  if ok and type(price) == "number" and price > 0 then return price end
  return nil
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
  local depositPerUnit = isCommodity and 0 or (vendorPrice * DepositRate)
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
  if FF.committedMinDepth > 0 and best.sellSideDepth < FF.committedMinDepth then return nil end
  if FF.committedMaxInvest > 0 and best.totalCost > FF.committedMaxInvest then return nil end

  local displayQuantity = (entry and entry.totalQuantity) or 0
  local relativeQuantity = (displayQuantity > 0) and (best.totalQuantity / displayQuantity * 100) or 0
  if FF.committedMaxQtyPct > 0 and relativeQuantity > FF.committedMaxQtyPct then return nil end

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
    sellSideDepth = best.sellSideDepth,
    depositCost = best.depositCost,
    roi = best.roi,
    isCommodity = isCommodity,
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
