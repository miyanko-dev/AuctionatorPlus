local _, AP = ...

-- TSM lines for the price-history tooltip: market value (with data age) and
-- the current price measured against it, shown while the auction house is
-- open and only when the TSM desktop app's data was captured this session.
-- Wraps AP.Tooltip.Apply from PriceHistory.lua instead of editing it, so
-- deleting this file and TSMFeed.lua fully revokes the feature.

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

  local pct = AP.Trend.Percent(AP.Bridge.AuctionPrice(itemLink), value)
  local trendText = AP.Trend.Colorize(pct, AP.Tooltip.TrendMode())
  if trendText then
    tooltip:AddDoubleLine("TSM Trend", trendText)
  end

  tooltip:Show()
end
