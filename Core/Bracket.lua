FF.Bracket = {}

local C = FF.Constants
local RATIO_FLOOR = 1 + C.MinPriceGapPercent / 100

function FF.Bracket.FindBest(listings, options)
  local n = #listings
  if n < 2 then return nil end

  table.sort(listings, function(a, b) return a.unitPrice < b.unitPrice end)

  local cut = options.cut
  local undercut = options.undercut
  local depositPerUnit = options.depositPerUnit or 0
  local vendorPrice = options.vendorPrice or 0
  local historicalPrice = options.historicalPrice
  local maxHistoricalMultiple = options.maxHistoricalMultiple or 0

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
      local sellPrice = topPrice * (1 - undercut)
      local effectiveSell = sellPrice * (1 - cut)

      local okVendor = effectiveSell >= vendorPrice
      local okHistorical = (not historicalPrice) or
        (maxHistoricalMultiple <= 0) or
        (sellPrice <= historicalPrice * maxHistoricalMultiple)

      if okVendor and okHistorical then
        local bracketCost = prefixCost[k]
        local bracketQty = prefixQty[k]
        local revenue = bracketQty * effectiveSell
        local depositCost = bracketQty * depositPerUnit
        local margin = revenue - bracketCost - depositCost
        local roi = bracketCost > 0 and (margin / bracketCost) or 0

        if margin > 0 and roi > bestROI then
          bestROI = roi
          local bracket = {}
          for j = 1, k do bracket[j] = listings[j] end
          best = {
            bracket = bracket,
            topPrice = topPrice,
            sellPrice = sellPrice,
            margin = margin,
            totalCost = bracketCost,
            totalQuantity = bracketQty,
            sellSideDepth = n - k,
            depositCost = depositCost,
            roi = roi,
          }
        end
      end
    end
  end

  return best
end
