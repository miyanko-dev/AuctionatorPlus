local _, AP = ...

-- TSM lines for the price-history tooltip: market value (with data age) and
-- the current price measured against it, shown while the auction house is
-- open and only when the TSM desktop app's data was captured this session.
-- Wraps AP.Tooltip.Apply from PriceHistory.lua instead of editing it, so
-- deleting this file and TSMFeed.lua fully revokes the feature.

-- Buy-to-flip verdict, a priority ladder over the decision data. Hard
-- failures first (not cheap on either baseline, or too little profit after
-- the AH cut), then reliability: local and TSM trend disagreeing by a wide
-- gap means the two baselines tell different stories about this item, so the
-- verdict caps at Risky. Only a solid sample bought at the historical floor
-- with agreeing trends is a clean Buy. Returns verdict, colour, and a short
-- detail (estimated profit, or the reason against buying).
local AH_CUT = 0.95
local MIN_MARGIN = 0.10     -- required profit as a share of the buy price
local FLOOR_SLACK = 1.05    -- how far above the historical floor still counts as "at" it
local SOLID_DAYS = 10
local TREND_GAP_LIMIT = 25  -- max percentage-point gap between local and TSM trend

local function FlipVerdict(price, tsmValue, tsmPct, stats)
  local localPct = stats and AP.Trend.Percent(price, stats.averageMinBuyout)
  if tsmPct >= 0 or (localPct and localPct >= 0) then
    return "Don't Buy", RED_FONT_COLOR, "not cheap"
  end

  -- Realistic resale: the middle of the recent floor band, never projected
  -- above TSM's market value; without scan history, market value itself.
  local exitPrice = tsmValue
  if stats and stats.rangeMin then
    exitPrice = math.min((stats.rangeMin + stats.rangeMax) / 2, tsmValue)
  end
  local profit = math.floor(exitPrice * AH_CUT - price)
  if profit < price * MIN_MARGIN then
    return "Don't Buy", RED_FONT_COLOR, "no margin"
  end

  local profitText = "~+" .. AP.Format.Money(profit)
  if localPct and math.abs(localPct - tsmPct) > TREND_GAP_LIMIT then
    return "Risky Buy", ORANGE_FONT_COLOR, "trends disagree, " .. profitText
  end

  if stats and stats.dayCount >= SOLID_DAYS and price <= stats.rangeMin * FLOOR_SLACK then
    return "Buy", GREEN_FONT_COLOR, profitText
  end
  local risk = (not stats or stats.dayCount < SOLID_DAYS) and "thin history" or "above floor"
  return "Risky Buy", ORANGE_FONT_COLOR, risk .. ", " .. profitText
end

local origApply = AP.Tooltip.Apply
AP.Tooltip.Apply = function(tooltip, itemLink)
  origApply(tooltip, itemLink)

  if not AP.ahOpen then return end

  local value = AP.TSMFeed.MarketValueForLink(itemLink)
  if not value then return end

  local label = "TSM Market Value"
  local age = AP.TSMFeed.AgeText()
  if age then
    label = label .. " (" .. age .. ")"
  end
  tooltip:AddDoubleLine(label, WHITE_FONT_COLOR:WrapTextInColorCode(AP.Format.Money(value)))

  local price = AP.Bridge.AuctionPrice(itemLink)
  local pct = AP.Trend.Percent(price, value)
  local trendText = AP.Trend.Colorize(pct, AP.Tooltip.TrendMode())
  if trendText then
    tooltip:AddDoubleLine("TSM Trend", trendText)

    local verdict, color, detail = FlipVerdict(price, value, pct, AP.History.ComputeForLink(itemLink))
    tooltip:AddDoubleLine("Flip Potential", color:WrapTextInColorCode(verdict)
      .. GRAY_FONT_COLOR:WrapTextInColorCode(" (" .. detail .. ")"))
  end

  tooltip:Show()
end
