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

function FF.History.Compute(dbKey)
  if type(dbKey) ~= "string" or dbKey == "" then return nil end
  local history = FetchHistory(dbKey)
  if not history or #history == 0 then return nil end

  local minSum, minCount = 0, 0
  for _, entry in ipairs(history) do
    local minSeen = tonumber(entry.minSeen)
    if minSeen and minSeen > 0 then
      minSum = minSum + minSeen
      minCount = minCount + 1
    end
  end

  if minCount == 0 then return nil end

  local mean = minSum / minCount
  local sqSum = 0
  for _, entry in ipairs(history) do
    local minSeen = tonumber(entry.minSeen)
    if minSeen and minSeen > 0 then
      local diff = minSeen - mean
      sqSum = sqSum + diff * diff
    end
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
