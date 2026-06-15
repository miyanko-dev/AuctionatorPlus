local _, AP = ...

AP.History = {}
AP.Trend = {}
AP.Tooltip = {}

-- ===== Price-history statistics =====

local function VolatilityBucket(cv, sampleCount)
  if not cv or sampleCount < 3 then return nil end
  if cv < 0.10 then return "Low" end
  if cv < 0.25 then return "Med" end
  return "High"
end

-- Day index Auctionator records for "today" (days since SCAN_DAY_0), matching
-- the rawDay on each history entry.
local function CurrentScanDay()
  return math.floor((time() - Auctionator.Constants.SCAN_DAY_0) / 86400)
end

function AP.History.Compute(dbKey)
  if type(dbKey) ~= "string" or dbKey == "" then return nil end

  local ok, history = pcall(Auctionator.Database.GetPriceHistory, Auctionator.Database, dbKey)
  if not ok or not history or #history == 0 then return nil end

  -- Keep only the last month of data so the trend tracks the current market.
  local cutoffDay = CurrentScanDay() - AP.Constants.HistoryWindowDays

  local recent = {}
  local minSum = 0
  for _, entry in ipairs(history) do
    local day = tonumber(entry.rawDay)
    local withinWindow = not day or day >= cutoffDay
    local minSeen = tonumber(entry.minSeen)
    if withinWindow and minSeen and minSeen > 0 then
      recent[#recent + 1] = minSeen
      minSum = minSum + minSeen
    end
  end

  local minCount = #recent
  if minCount == 0 then return nil end

  local mean = minSum / minCount
  local sqSum = 0
  for _, minSeen in ipairs(recent) do
    local diff = minSeen - mean
    sqSum = sqSum + diff * diff
  end
  local stdev = math.sqrt(sqSum / minCount)
  local cv = mean > 0 and (stdev / mean) or 0

  return {
    sampleCount      = minCount,
    averageMinBuyout = math.floor(mean + 0.5),
    volatility       = cv,
    volatilityBucket = VolatilityBucket(cv, minCount),
  }
end

-- ===== Trend percentage =====

-- Colour modes for a trend percentage.
AP.Trend.UP_GREEN = "upGreen" -- increase green, decrease red (selling, native AH)
AP.Trend.UP_RED   = "upRed"   -- increase red, decrease green (shopping / browse)
AP.Trend.NEUTRAL  = "neutral" -- always white

-- Whole-percent deviation of currentPrice from average. nil when either input
-- is missing or non-positive.
function AP.Trend.Percent(currentPrice, average)
  if type(currentPrice) ~= "number" or currentPrice <= 0 then return nil end
  if type(average) ~= "number" or average <= 0 then return nil end
  return math.floor((currentPrice - average) / average * 100 + 0.5)
end

-- Historical average min buyout for an item link, via Auctionator's price
-- database. nil when there is no usable history.
function AP.Trend.AverageFor(itemLink)
  local dbKey = AP.Bridge.DBKeyForLink(itemLink)
  if not dbKey then return nil end

  local stats = AP.History.Compute(dbKey)
  if not stats or not stats.averageMinBuyout or stats.averageMinBuyout <= 0 then
    return nil
  end
  return stats.averageMinBuyout
end

-- "+N%" / "-N%" / "0%" wrapped in the colour dictated by mode. A nil pct yields
-- nil so callers can skip an empty trend.
function AP.Trend.Colorize(pct, mode)
  if type(pct) ~= "number" then return nil end

  local text = (pct == 0) and "0%" or string.format("%+d%%", pct)

  local color = WHITE_FONT_COLOR
  if pct ~= 0 and mode ~= AP.Trend.NEUTRAL then
    local increaseGood = mode == AP.Trend.UP_GREEN
    if (pct > 0) == increaseGood then
      color = GREEN_FONT_COLOR
    else
      color = RED_FONT_COLOR
    end
  end

  return color:WrapTextInColorCode(text)
end

-- ===== Item tooltip lines =====

-- Trend colour depends on the active auction-house view: the selling tab and
-- the native Browse/Auctions tabs treat price increases as good (green); the
-- shopping/browse tab reverses it (increases red). Any other view shows the
-- trend without a verdict (white). Uses IsVisible so a deselected Auctionator
-- tab (its wrapper hidden) does not register as active.
local function TrendMode()
  if _G.AuctionatorShoppingFrame and _G.AuctionatorShoppingFrame:IsVisible() then
    return AP.Trend.UP_RED
  end
  if _G.AuctionatorSellingFrame and _G.AuctionatorSellingFrame:IsVisible() then
    return AP.Trend.UP_GREEN
  end
  if _G.AuctionFrameBrowse and _G.AuctionFrameBrowse:IsVisible() then
    return AP.Trend.UP_GREEN
  end
  if _G.AuctionFrameAuctions and _G.AuctionFrameAuctions:IsVisible() then
    return AP.Trend.UP_GREEN
  end
  return AP.Trend.NEUTRAL
end

function AP.Tooltip.Apply(tooltip, itemLink)
  if not tooltip or not itemLink then return end

  local dbKey = AP.Bridge.DBKeyForLink(itemLink)
  if not dbKey then return end

  local stats = AP.History.Compute(dbKey)
  if not stats or not stats.averageMinBuyout or stats.averageMinBuyout <= 0 then
    return
  end

  local cfg = AP.Constants.Tooltip
  tooltip:AddDoubleLine(
    cfg.AverageLabel,
    WHITE_FONT_COLOR:WrapTextInColorCode(AP.Format.Money(stats.averageMinBuyout)))

  -- The trend percentage is only meaningful at the auction house, so it shows
  -- only while the AH is open and is coloured for the active view.
  if AP.ahOpen then
    local pct = AP.Trend.Percent(AP.Bridge.AuctionPrice(itemLink), stats.averageMinBuyout)
    local trendText = AP.Trend.Colorize(pct, TrendMode())
    if trendText then
      tooltip:AddDoubleLine(cfg.TrendLabel, trendText)
    end
  end

  -- Trigger a resize so newly added lines render inside the tooltip frame.
  tooltip:Show()
end

-- ===== Tooltip hooks =====

-- Item-setting methods that exist on this client get a post-hook; the per-name
-- check matters because the list spans several client flavors.
local TOOLTIP_METHODS = {
  "SetBagItem", "SetBuybackItem", "SetMerchantItem", "SetInventoryItem",
  "SetGuildBankItem", "SetLootItem", "SetLootRollItem",
  "SetQuestItem", "SetQuestLogItem", "SetSendMailItem", "SetInboxItem",
  "SetTradePlayerItem", "SetTradeTargetItem", "SetAuctionItem",
  "SetItemByID", "SetHyperlink", "SetTradeSkillItem", "SetCraftItem",
  "SetItemByGUID", "SetRecipeReagentItem", "SetRecipeResultItem",
  "SetItemKey",
}

local function Dispatch(tooltip)
  if not tooltip or not tooltip.GetItem then return end
  local _, link = tooltip:GetItem()
  if not link or link == "" then return end
  pcall(AP.Tooltip.Apply, tooltip, link)
end

for _, methodName in ipairs(TOOLTIP_METHODS) do
  if GameTooltip[methodName] then
    hooksecurefunc(GameTooltip, methodName, Dispatch)
  end
end
hooksecurefunc(ItemRefTooltip, "SetHyperlink", Dispatch)
