FF.History = {}

local SECONDS_PER_DAY = 86400

local function FetchHistory(dbKey)
  if not (Auctionator and Auctionator.Database and Auctionator.Database.GetPriceHistory) then
    return nil
  end
  local ok, history = pcall(Auctionator.Database.GetPriceHistory, Auctionator.Database, dbKey)
  if not ok then return nil end
  return history
end

local function WeekdayFromEntry(entry)
  local rawDay = entry and entry.rawDay
  local scanDay0 = Auctionator and Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0
  if rawDay and scanDay0 then
    return date("*t", scanDay0 + rawDay * SECONDS_PER_DAY).wday
  end
  if entry and type(entry.date) == "number" then
    return date("*t", entry.date).wday
  end
  return nil
end

function FF.History.Compute(dbKey)
  if type(dbKey) ~= "string" or dbKey == "" then return nil end
  local history = FetchHistory(dbKey)
  if not history or #history == 0 then return nil end

  local minSum, minCount = 0, 0
  local wdaySum, wdayCount = {}, {}

  for _, entry in ipairs(history) do
    local minSeen = tonumber(entry.minSeen)
    if minSeen and minSeen > 0 then
      minSum = minSum + minSeen
      minCount = minCount + 1
      local wday = WeekdayFromEntry(entry)
      if wday then
        wdaySum[wday] = (wdaySum[wday] or 0) + minSeen
        wdayCount[wday] = (wdayCount[wday] or 0) + 1
      end
    end
  end

  if minCount == 0 then return nil end

  local highestWeekday, highestAvg
  local lowestWeekday, lowestAvg
  local distinctWdays = 0
  for wday = 1, 7 do
    local count = wdayCount[wday]
    if count and count > 0 then
      distinctWdays = distinctWdays + 1
      local avg = wdaySum[wday] / count
      if not highestAvg or avg > highestAvg then
        highestWeekday, highestAvg = wday, avg
      end
      if not lowestAvg or avg < lowestAvg then
        lowestWeekday, lowestAvg = wday, avg
      end
    end
  end

  local hasTrend = distinctWdays >= 2
  return {
    averageMinBuyout = math.floor(minSum / minCount + 0.5),
    highestWeekday   = hasTrend and highestWeekday or nil,
    lowestWeekday    = hasTrend and lowestWeekday or nil,
  }
end
