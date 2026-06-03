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
  if type(price) ~= "number" or price <= 0 then return nil end
  return price
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

local function White(text)
  if WHITE_FONT_COLOR and WHITE_FONT_COLOR.WrapTextInColorCode then
    return WHITE_FONT_COLOR:WrapTextInColorCode(tostring(text))
  end
  return "|cffffffff" .. tostring(text) .. "|r"
end

-- Trend colour depends on the active auction-house view: the selling tab and
-- the native Browse/Auctions tabs treat price increases as good (green); the
-- shopping/browse tab reverses it (increases red). Any other view shows the
-- trend without a verdict (white). Uses IsVisible so a deselected Auctionator
-- tab (its wrapper hidden) does not register as active.
local function TrendMode()
  if _G.AuctionatorShoppingFrame and _G.AuctionatorShoppingFrame:IsVisible() then
    return FF.Trend.UP_RED
  end
  if _G.AuctionatorSellingFrame and _G.AuctionatorSellingFrame:IsVisible() then
    return FF.Trend.UP_GREEN
  end
  if _G.AuctionFrameBrowse and _G.AuctionFrameBrowse:IsVisible() then
    return FF.Trend.UP_GREEN
  end
  if _G.AuctionFrameAuctions and _G.AuctionFrameAuctions:IsVisible() then
    return FF.Trend.UP_GREEN
  end
  return FF.Trend.NEUTRAL
end

function FF.Tooltip.Apply(tooltip, itemLink)
  if not tooltip or not itemLink then return end

  local dbKey = DBKeyForLink(itemLink)
  if not dbKey then return end

  local stats = FF.History.Compute(dbKey)
  if not stats or not stats.averageMinBuyout or stats.averageMinBuyout <= 0 then
    return
  end

  local cfg = FF.Constants.Tooltip
  tooltip:AddDoubleLine(cfg.AverageLabel, White(FF.Format.Money(stats.averageMinBuyout)))

  -- The trend percentage is only meaningful at the auction house, so it shows
  -- only while the AH is open and is coloured for the active view.
  if FF.ahOpen then
    local pct = FF.Trend.Percent(CurrentAuctionPrice(itemLink), stats.averageMinBuyout)
    local trendText = FF.Trend.Colorize(pct, TrendMode())
    if trendText then
      tooltip:AddDoubleLine(cfg.TrendLabel, trendText)
    end
  end

  -- Trigger a resize so newly added lines render inside the tooltip frame
  if tooltip.Show then tooltip:Show() end
end
