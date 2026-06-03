FF = FF or {}

FF.collected = {}
FF.seenKeys = {}
FF.scanned = {}
FF.flips = {}

FF.panel = nil
FF.toggleButton = nil
FF.hasScanned = false

-- Tracks whether the auction house is currently open (set in Bootstrap).
FF.ahOpen = false

FF.sortProperty = "roi"
FF.sortDirection = "desc"

FF.committedMaxQtyPct = 0
FF.committedMaxInvest = 0
FF.committedMinProfit = 0
FF.committedMinROI = 0.20

FF.fullScanButton = nil

-- Persisted options (loaded from AuctionatorPlusDB on PLAYER_LOGIN).
FF.Settings = {
  checkOtherItems = false,
  sameStats = false,
}

function FF.Settings.Load()
  local db = _G.AuctionatorPlusDB
  if type(db) ~= "table" then
    db = {}
    _G.AuctionatorPlusDB = db
  end
  if type(db.checkOtherItems) == "boolean" then
    FF.Settings.checkOtherItems = db.checkOtherItems
  end
  if type(db.sameStats) == "boolean" then
    FF.Settings.sameStats = db.sameStats
  end
end

function FF.Settings.Save()
  local db = _G.AuctionatorPlusDB
  if type(db) ~= "table" then
    db = {}
    _G.AuctionatorPlusDB = db
  end
  db.checkOtherItems = FF.Settings.checkOtherItems
  db.sameStats = FF.Settings.sameStats
end
