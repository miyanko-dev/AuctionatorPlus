local _, AP = ...

AP.History = {}
AP.Trend = {}
AP.Tooltip = {}

-- ===== Price-history statistics =====
local MIN_TRIM_SAMPLES = 8 -- below this a quartile trim is too thin to stop same-side freak days, the median is safer

local function medianOf(sorted)
    local count = #sorted
    local mid = math.floor(count / 2)
    if count % 2 == 0 then
        return (sorted[mid] + sorted[mid + 1]) / 2
    end
    return sorted[mid + 1]
end

-- Interquartile mean of daily prices: dropping the cheapest and priciest quarter removes dump days and thin-supply days by construction, with no tuning constants to misjudge a market.
local function interquartileMean(prices)
    table.sort(prices)
    if #prices < MIN_TRIM_SAMPLES then
        return medianOf(prices)
    end

    local trim = math.floor(#prices * 0.25)
    local total, count = 0, 0
    for index = trim + 1, #prices - trim do
        total = total + prices[index]
        count = count + 1
    end
    return total / count
end

-- Match Auctionator's day index (days since SCAN_DAY_0), as carried by each entry's rawDay.
local function currentScanDay()
    return math.floor((time() - Auctionator.Constants.SCAN_DAY_0) / 86400)
end

function AP.History.Compute(dbKey)
    if type(dbKey) ~= "string" or dbKey == "" then return nil end

    local ok, history = pcall(Auctionator.Database.GetPriceHistory, Auctionator.Database, dbKey)
    if not ok or not history or #history == 0 then return nil end

    -- Keep only the history window so the trend tracks the current market.
    local cutoffDay = currentScanDay() - AP.Constants.HistoryWindowDays

    local recent = {}
    for _, entry in ipairs(history) do
        local day = tonumber(entry.rawDay)
        local withinWindow = not day or day > cutoffDay
        local minSeen = tonumber(entry.minSeen)
        if withinWindow and minSeen and minSeen > 0 then
            recent[#recent + 1] = minSeen
        end
    end

    if #recent == 0 then return nil end

    return { averageMinBuyout = math.floor(interquartileMean(recent) + 0.5) }
end

-- Prefer the first db key with usable history, so suffixed gear measures against its own suffix market before the pooled base item, matching Auctionator's price lookups.
function AP.History.ComputeForLink(itemLink)
    local dbKeys = AP.Bridge.DBKeysForLink(itemLink)
    if not dbKeys then return nil end

    for _, dbKey in ipairs(dbKeys) do
        local stats = AP.History.Compute(dbKey)
        if stats and stats.averageMinBuyout and stats.averageMinBuyout > 0 then
            return stats
        end
    end
    return nil
end

-- ===== Trend percentage =====
-- Colour modes for a trend percentage.
AP.Trend.UP_GREEN = "upGreen" -- increase green, decrease red (selling, native AH)
AP.Trend.UP_RED   = "upRed"   -- increase red, decrease green (shopping / browse)
AP.Trend.NEUTRAL  = "neutral" -- always white

-- Whole-percent deviation of currentPrice from average; nil when either input is unusable.
function AP.Trend.Percent(currentPrice, average)
    if type(currentPrice) ~= "number" or currentPrice <= 0 then return nil end
    if type(average) ~= "number" or average <= 0 then return nil end
    return math.floor((currentPrice - average) / average * 100 + 0.5)
end

-- Historical average min buyout for an item link; nil without usable history.
function AP.Trend.AverageFor(itemLink)
    local stats = AP.History.ComputeForLink(itemLink)
    return stats and stats.averageMinBuyout
end

-- "+N%" / "-N%" / "0%" wrapped in the colour dictated by mode; nil pct yields nil so callers can skip an empty trend.
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
-- Reverse the colours in buying views (a price increase is bad for a buyer); IsVisible so a deselected Auctionator tab does not register as active.
function AP.Tooltip.TrendMode()
    if _G.AuctionatorShoppingFrame and _G.AuctionatorShoppingFrame:IsVisible() then
        return AP.Trend.UP_RED
    end
    if _G.AuctionFrameBrowse and _G.AuctionFrameBrowse:IsVisible() then
        return AP.Trend.UP_RED
    end
    return AP.Trend.UP_GREEN
end

-- Add an Item Value and a Price Trend section; rows without data stay silent, Auctionator's own vendor and auction lines are left untouched.
function AP.Tooltip.Apply(tooltip, itemLink)
    if not tooltip or not itemLink then return end

    local auction = AP.Bridge.AuctionPrice(itemLink)
    local stats = AP.History.ComputeForLink(itemLink)
    local average = stats and stats.averageMinBuyout
    local tsmMarket = AP.TSMFeed and AP.TSMFeed.SmoothedValueForLink(itemLink)

    if not (average or tsmMarket) then return end

    -- Tag the TSM row with the app snapshot age so stale data is visible at a glance.
    local tsmLabel = "TSM"
    local age = AP.TSMFeed and AP.TSMFeed.AgeText()
    if age then
        tsmLabel = "TSM (" .. age .. ")"
    end

    local mode = AP.Tooltip.TrendMode()
    local trendLocal = AP.Trend.Colorize(AP.Trend.Percent(auction, average), mode)
    local trendMarket = AP.Trend.Colorize(AP.Trend.Percent(auction, tsmMarket), mode)

    local function addRow(label, text)
        if text then
            tooltip:AddDoubleLine(label, text, 1, 1, 1, 1, 1, 1)
        end
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("Item Value", NORMAL_FONT_COLOR:GetRGB())
    addRow("Auctionator", average and AP.Format.Money(average))
    addRow(tsmLabel, tsmMarket and AP.Format.Money(tsmMarket))

    if trendLocal or trendMarket then
        tooltip:AddLine(" ")
        tooltip:AddLine("Price Trend", NORMAL_FONT_COLOR:GetRGB())
        addRow("Auctionator", trendLocal)
        addRow("TSM", trendMarket)
    end

    -- Trigger a resize so newly added lines render inside the tooltip frame.
    tooltip:Show()
end

-- ===== Tooltip hooks =====
-- Hook only the item-setting methods that exist on this client; the list spans several flavors.
local TOOLTIP_METHODS = {
    "SetBagItem", "SetBuybackItem", "SetMerchantItem", "SetInventoryItem",
    "SetGuildBankItem", "SetLootItem", "SetLootRollItem",
    "SetQuestItem", "SetQuestLogItem", "SetSendMailItem", "SetInboxItem",
    "SetTradePlayerItem", "SetTradeTargetItem", "SetAuctionItem",
    "SetItemByID", "SetHyperlink", "SetTradeSkillItem", "SetCraftItem",
    "SetItemByGUID", "SetRecipeReagentItem", "SetRecipeResultItem",
    "SetItemKey",
}

local function dispatch(tooltip)
    if not tooltip or not tooltip.GetItem then return end
    local _, link = tooltip:GetItem()
    if not link or link == "" then return end
    pcall(AP.Tooltip.Apply, tooltip, link)
end

for _, methodName in ipairs(TOOLTIP_METHODS) do
    if GameTooltip[methodName] then
        hooksecurefunc(GameTooltip, methodName, dispatch)
    end
end
hooksecurefunc(ItemRefTooltip, "SetHyperlink", dispatch)
