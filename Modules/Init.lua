local _, AP = ...

-- Shopping-search results collected for the Arbitrage scan (reset per search).
AP.collected = {}
AP.seenKeys = {}
AP.scanned = {}
AP.flips = {}

AP.hasScanned = false

-- Tracks whether the auction house is currently open (set in Bootstrap).
AP.ahOpen = false

AP.sortProperty = "roi"
AP.sortDirection = "desc"

AP.committedMaxQtyPct = 0
AP.committedMaxInvest = 0
AP.committedMinProfit = 0
AP.committedMinROI = 0.20

AP.Constants = {
  CallerID = "AuctionatorPlus",

  DefaultMinROIPercent = 20,
  MinGapPercent = 15,
  AHCutPercent = 5,
  DepositPercent = 5,
  DefaultUndercutPercent = 2,
  HistoricalMultipleCap = 3,
  HistoryWindowDays = 21,  -- matches Auctionator's default price-history retention

  PanelWidth = 950,
  PanelHeight = 540,
  RowHeight = 28,

  Columns = {
    Item        = 180,
    RelQty      = 90,
    Underpriced = 80,
    Vol         = 45,
    Sellers     = 55,
    Cost        = 95,
    Profit      = 95,
    ROI         = 55,
    Gap         = 8,
  },

  Tooltip = {
    AverageLabel = "Average Min. Buyout",
    TrendLabel   = "Trend",
  },
}

-- Persisted options (loaded from AuctionatorPlusDB on PLAYER_LOGIN).
AP.Settings = {
  checkOtherItems = false,
  sameStats = false,
}

local function EnsureDB()
  if type(AuctionatorPlusDB) ~= "table" then
    AuctionatorPlusDB = {}
  end
  return AuctionatorPlusDB
end

function AP.LoadSettings()
  local db = EnsureDB()
  if type(db.checkOtherItems) == "boolean" then
    AP.Settings.checkOtherItems = db.checkOtherItems
  end
  if type(db.sameStats) == "boolean" then
    AP.Settings.sameStats = db.sameStats
  end
end

function AP.SaveSettings()
  local db = EnsureDB()
  db.checkOtherItems = AP.Settings.checkOtherItems
  db.sameStats = AP.Settings.sameStats
end

AP.Format = {}

function AP.Format.StripItemColor(name)
  if not name then return "" end
  name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return name:lower()
end

function AP.Format.CleanItemText(text)
  if not text then return "?" end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  text = text:gsub("|T[^|]+|t", "")
  text = text:gsub("|H[^|]+|h", ""):gsub("|h", "")
  return strtrim(text)
end

function AP.Format.Money(copper)
  if not copper or copper <= 0 then
    return "0g"
  end
  return Auctionator.Utilities.CreatePaddedMoneyString(copper)
end
