FF.Tooltip = {}

local function CurrentAuctionPrice(itemLink)
  if not (Auctionator and Auctionator.API and Auctionator.API.v1
      and Auctionator.API.v1.GetAuctionPriceByItemLink) then
    return nil
  end
  local ok, price = pcall(
    Auctionator.API.v1.GetAuctionPriceByItemLink,
    FF.Constants.Tooltip.CallerID,
    itemLink
  )
  if not ok then return nil end
  return price
end

local function FormatTrend(current, average)
  if not current or not average or average <= 0 then return nil end
  local pct = math.floor((current - average) / average * 100 + 0.5)
  if pct == 0 then return "0%" end
  return string.format("%+d%%", pct)
end

local function DBKeyForLink(itemLink)
  if not (Auctionator and Auctionator.Utilities
      and Auctionator.Utilities.BasicDBKeyFromLink) then
    return nil
  end
  local ok, key = pcall(Auctionator.Utilities.BasicDBKeyFromLink, itemLink)
  if not ok then return nil end
  return key
end

function FF.Tooltip.Apply(tooltip, itemLink)
  if not tooltip or not itemLink then return end
  if not (FF.Adapter and FF.Adapter.IsAHVisible
      and FF.Adapter.IsAHVisible()) then
    return
  end
  if FF.Adapter.ShouldSuppressTooltip and FF.Adapter.ShouldSuppressTooltip(tooltip) then
    return
  end

  local dbKey = DBKeyForLink(itemLink)
  if not dbKey then return end

  local stats = FF.History.Compute(dbKey)
  if not stats then return end

  local cfg = FF.Constants.Tooltip
  local moneyFn = FF.Format.Money

  local function White(text)
    if WHITE_FONT_COLOR and WHITE_FONT_COLOR.WrapTextInColorCode then
      return WHITE_FONT_COLOR:WrapTextInColorCode(tostring(text))
    end
    return "|cffffffff" .. tostring(text) .. "|r"
  end

  tooltip:AddLine(" ")
  tooltip:AddDoubleLine(cfg.AverageLabel, White(moneyFn(stats.averageMinBuyout)))

  local trendText = FormatTrend(CurrentAuctionPrice(itemLink), stats.averageMinBuyout)
  if trendText then
    tooltip:AddDoubleLine(cfg.TrendLabel, White(trendText))
  end

  if stats.highestWeekday then
    local name = FF.Format.WeekdayName(stats.highestWeekday)
    if name then
      tooltip:AddDoubleLine(cfg.HighestDayLabel, White(name))
    end
  end

  if stats.lowestWeekday then
    local name = FF.Format.WeekdayName(stats.lowestWeekday)
    if name then
      tooltip:AddDoubleLine(cfg.LowestDayLabel, White(name))
    end
  end
end
