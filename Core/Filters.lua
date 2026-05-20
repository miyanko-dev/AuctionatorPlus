FF.Filters = {}

local DefaultCut = FF.Constants.DefaultAHCutPercent / 100
local DefaultRatio = FF.Constants.PriceJumpRatio

function FF.Filters.Commit()
  local panel = FF.panel
  if not panel then return end

  local pct = tonumber(panel.MinMarginEditBox:GetText())
  FF.committedRatio = (pct and pct > 0) and (1 + pct / 100) or DefaultRatio

  local gold = tonumber(panel.MaxInvestEditBox:GetText())
  FF.committedMaxInvest = (gold and gold > 0) and (gold * 10000) or 0

  local qty = tonumber(panel.MinQuantityEditBox:GetText())
  FF.committedMinQuantity = (qty and qty > 0) and qty or 1

  local orderQty = tonumber(panel.MaxOrderQtyEditBox:GetText())
  FF.committedMaxOrderQty = (orderQty and orderQty > 0) and orderQty or 0

  local profitGold = tonumber(panel.MinProfitEditBox:GetText())
  FF.committedMinProfit = (profitGold and profitGold > 0) and (profitGold * 10000) or 0

  local qtyPct = tonumber(panel.MaxQtyPctEditBox:GetText())
  FF.committedMaxQtyPct = (qtyPct and qtyPct > 0) and qtyPct or 0

  local cutPct = tonumber(panel.AHCutEditBox:GetText())
  FF.committedCut = (cutPct and cutPct >= 0) and (cutPct / 100) or DefaultCut
end

function FF.Filters.BuildFlip(scannedRecord)
  local listings = scannedRecord.listings
  if not listings or #listings < 2 then return nil end

  local bracket, topPrice = FF.Bracket.Find(listings, FF.committedRatio)
  if not bracket or not topPrice then return nil end

  local summary = FF.Bracket.Summarize(bracket, topPrice, FF.committedCut)
  if summary.margin <= 0 then return nil end

  local entry = scannedRecord.entry
  local displayQuantity = (entry and entry.totalQuantity) or 0

  if FF.committedMaxInvest > 0 and summary.totalCost > FF.committedMaxInvest then return nil end
  if FF.committedMinQuantity > 0 and displayQuantity < FF.committedMinQuantity then return nil end
  if FF.committedMaxOrderQty > 0 and summary.totalQuantity > FF.committedMaxOrderQty then return nil end
  if FF.committedMinProfit > 0 and summary.margin < FF.committedMinProfit then return nil end
  if FF.committedMaxQtyPct > 0 and displayQuantity > 0 then
    local pct = (summary.totalQuantity / displayQuantity) * 100
    if pct > FF.committedMaxQtyPct then return nil end
  end

  local firstAuction = entry and entry.entries and entry.entries[1]
  local itemLink = (entry and entry.itemLink) or (firstAuction and firstAuction.itemLink)
  local itemName = entry and entry.itemName
  if not itemName and itemLink then
    itemName = GetItemInfo(itemLink)
  end

  return {
    entry = entry,
    itemKey = entry and entry.itemKey,
    itemLink = itemLink,
    itemName = itemName,
    topPrice = summary.topPrice,
    margin = summary.margin,
    totalCost = summary.totalCost,
    totalQuantity = summary.totalQuantity,
    displayQuantity = displayQuantity,
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
  local prop = FF.sortProperty or "totalCost"
  local asc = (FF.sortDirection or "asc") == "asc"
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
