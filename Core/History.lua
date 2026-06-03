FF.History = {}

local function FetchHistory(dbKey)
  if not (Auctionator and Auctionator.Database and Auctionator.Database.GetPriceHistory) then
    return nil
  end
  local ok, history = pcall(Auctionator.Database.GetPriceHistory, Auctionator.Database, dbKey)
  if not ok then return nil end
  return history
end

local function VolatilityBucket(cv, sampleCount)
  if not cv or sampleCount < 3 then return nil end
  if cv < 0.10 then return "Low" end
  if cv < 0.25 then return "Med" end
  return "High"
end

-- Day index Auctionator records for "today" (days since SCAN_DAY_0), matching
-- the rawDay on each history entry. nil when the reference epoch is missing, in
-- which case the caller leaves the data unfiltered.
local function CurrentScanDay()
  local epoch0 = Auctionator and Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0
  if type(epoch0) ~= "number" then return nil end
  return math.floor((time() - epoch0) / 86400)
end

function FF.History.Compute(dbKey)
  if type(dbKey) ~= "string" or dbKey == "" then return nil end
  local history = FetchHistory(dbKey)
  if not history or #history == 0 then return nil end

  -- Keep only the last month of data so the trend tracks the current market.
  local today = CurrentScanDay()
  local cutoffDay = today and (today - FF.Constants.HistoryWindowDays)

  local recent = {}
  local minSum = 0
  for _, entry in ipairs(history) do
    local day = tonumber(entry.rawDay)
    local withinWindow = not cutoffDay or not day or day >= cutoffDay
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
