FF.Trend = {}

-- Colour modes for a trend percentage.
FF.Trend.UP_GREEN = "upGreen" -- increase green, decrease red (selling, native AH)
FF.Trend.UP_RED   = "upRed"   -- increase red, decrease green (shopping / browse)
FF.Trend.NEUTRAL  = "neutral" -- always white

-- Whole-percent deviation of currentPrice from average. nil when either input
-- is missing or non-positive.
function FF.Trend.Percent(currentPrice, average)
  if type(currentPrice) ~= "number" or currentPrice <= 0 then return nil end
  if type(average) ~= "number" or average <= 0 then return nil end
  return math.floor((currentPrice - average) / average * 100 + 0.5)
end

-- Historical average min buyout for an item link, via Auctionator's price
-- database. nil when there is no usable history.
function FF.Trend.AverageFor(itemLink)
  if not itemLink then return nil end
  if not (Auctionator and Auctionator.Utilities
      and Auctionator.Utilities.BasicDBKeyFromLink) then
    return nil
  end

  local ok, dbKey = pcall(Auctionator.Utilities.BasicDBKeyFromLink, itemLink)
  if not ok or not dbKey then return nil end

  local stats = FF.History.Compute(dbKey)
  if not stats or not stats.averageMinBuyout or stats.averageMinBuyout <= 0 then
    return nil
  end
  return stats.averageMinBuyout
end

-- "+N%" / "-N%" / "0%" wrapped in the colour dictated by mode. A nil pct yields
-- nil so callers can skip an empty trend.
function FF.Trend.Colorize(pct, mode)
  if type(pct) ~= "number" then return nil end

  local text = (pct == 0) and "0%" or string.format("%+d%%", pct)

  local color = WHITE_FONT_COLOR
  if pct ~= 0 and mode ~= FF.Trend.NEUTRAL then
    local increaseGood = mode == FF.Trend.UP_GREEN
    if (pct > 0) == increaseGood then
      color = GREEN_FONT_COLOR
    else
      color = RED_FONT_COLOR
    end
  end

  return color:WrapTextInColorCode(text)
end
