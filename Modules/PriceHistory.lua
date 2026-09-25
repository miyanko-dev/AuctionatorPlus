local _, AP = ...

-- Price-history statistics, the Relative Value and the tooltip rows; each client's half hooks its tooltips and defines AP.Tooltip.TrendMode
AP.Trend = {}
AP.Tooltip = {}

-- ===== Price-history statistics =====
-- 14 days keeps the local average comparable to TSM's market value window
local HISTORY_WINDOW_DAYS = 14

-- Below this a quartile trim is too thin to stop same-side freak days, the median is safer
local MIN_TRIM_SAMPLES = 8

local function medianOf(sorted)
    local count = #sorted
    local mid = math.floor(count / 2)
    if count % 2 == 0 then
        return (sorted[mid] + sorted[mid + 1]) / 2
    end
    return sorted[mid + 1]
end

-- Interquartile mean of daily prices: dropping the cheapest and priciest quarter removes dump days and thin-supply days by construction, with no tuning constants to misjudge a market
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

-- Auctionator's day index (days since SCAN_DAY_0), as carried by each history row's rawDay
local function currentScanDay()
    return math.floor((time() - Auctionator.Constants.SCAN_DAY_0) / 86400)
end

-- Average minimum buyout inside the history window for one price-database key; nil without usable history
local function averageFor(dbKey)
    local cutoffDay = currentScanDay() - HISTORY_WINDOW_DAYS
    local recent = {}
    for _, entry in ipairs(AP.Bridge.PriceHistory(dbKey)) do
        local day = tonumber(entry.rawDay)
        local minSeen = tonumber(entry.minSeen)
        if (not day or day > cutoffDay) and minSeen and minSeen > 0 then
            recent[#recent + 1] = minSeen
        end
    end
    if #recent == 0 then return nil end
    return math.floor(interquartileMean(recent) + 0.5)
end

-- First key with usable history, so a suffix or item-level key measures against its own market before the pooled base item, matching Auctionator's price lookups
function AP.Trend.AverageFor(itemRef)
    for _, dbKey in ipairs(AP.Bridge.DBKeys(itemRef) or {}) do
        local average = averageFor(dbKey)
        if average and average > 0 then return average end
    end
    return nil
end

-- ===== Trend percentage =====
-- Colour modes: UP_GREEN for selling (an increase is good), UP_RED for buying
AP.Trend.UP_GREEN = "upGreen"
AP.Trend.UP_RED = "upRed"

-- Whole-percent deviation of currentPrice from average; nil when either input is unusable
function AP.Trend.Percent(currentPrice, average)
    if type(currentPrice) ~= "number" or currentPrice <= 0 then return nil end
    if type(average) ~= "number" or average <= 0 then return nil end
    return math.floor((currentPrice - average) / average * 100 + 0.5)
end

-- Relative Value for the listings: against Auctionator's average alone, or the mean of the Auctionator and TSM indices when both exist
function AP.Trend.IndexFor(currentPrice, itemRef)
    local localPct = AP.Trend.Percent(currentPrice, AP.Trend.AverageFor(itemRef))
    if not localPct then return nil end
    local tsmPct = AP.Trend.Percent(currentPrice, AP.TSM.MarketValueFor(itemRef))
    if not tsmPct then return localPct end
    return math.floor((localPct + tsmPct) / 2 + 0.5)
end

-- "+N%" / "-N%" / "0%" wrapped in the colour dictated by mode; nil pct yields nil so callers can skip an empty trend
function AP.Trend.Colorize(pct, mode)
    if type(pct) ~= "number" then return nil end

    if pct == 0 then return WHITE_FONT_COLOR:WrapTextInColorCode("0%") end
    local increaseGood = mode == AP.Trend.UP_GREEN
    local color = ((pct > 0) == increaseGood) and GREEN_FONT_COLOR or RED_FONT_COLOR
    return color:WrapTextInColorCode(string.format("%+d%%", pct))
end

-- ===== Item tooltip rows =====
local function addRow(tooltip, label, text)
    if text then
        tooltip:AddDoubleLine(label, text, 1, 1, 1, 1, 1, 1)
    end
end

-- Auctionator's history is daily; "<1d" covers a scan from today
local function ageLabel(days)
    if not days then return "Average Price (Auctionator)" end
    return ("Average Price (Auctionator %s)"):format(days < 1 and "<1d" or (days .. "d"))
end

-- Averages first, then the Relative Value of the last known price against each, then the sale rate; rows without data stay silent and Auctionator's own lines are left untouched
function AP.Tooltip.AddPriceRows(tooltip, itemLink)
    local average = AP.Trend.AverageFor(itemLink)
    local tsmMarket = AP.TSM.MarketValueFor(itemLink)
    if not (average or tsmMarket) then return end

    local auction = AP.Bridge.AuctionPrice(itemLink)
    local mode = AP.Tooltip.TrendMode()
    tooltip:AddLine(" ")
    addRow(tooltip, ageLabel(AP.Bridge.PriceAge(itemLink)), average and AP.Bridge.Money(average))
    addRow(tooltip, "Average Price (TSM)", tsmMarket and AP.Bridge.Money(tsmMarket))
    addRow(tooltip, "Relative Value (Auctionator)", AP.Trend.Colorize(AP.Trend.Percent(auction, average), mode))
    addRow(tooltip, "Relative Value (TSM)", AP.Trend.Colorize(AP.Trend.Percent(auction, tsmMarket), mode))
    addRow(tooltip, "Sale Rate (TSM)", AP.TSM.SaleRateText(itemLink))

    -- Resize so the added lines render inside the tooltip frame
    tooltip:Show()
end
