local _, AP = ...

AP.Constants = {
    CallerID = "AuctionatorPlus",

    HistoryWindowDays = 21,  -- matches Auctionator's default price-history retention
}

-- Persist options in AuctionatorPlusDB; loaded on PLAYER_LOGIN.
AP.Settings = {
    checkOtherItems = false,
    sameStats = false,
}

local function ensureDB()
    if type(AuctionatorPlusDB) ~= "table" then
        AuctionatorPlusDB = {}
    end
    return AuctionatorPlusDB
end

function AP.LoadSettings()
    local db = ensureDB()
    if type(db.checkOtherItems) == "boolean" then
        AP.Settings.checkOtherItems = db.checkOtherItems
    end
    if type(db.sameStats) == "boolean" then
        AP.Settings.sameStats = db.sameStats
    end
end

function AP.SaveSettings()
    local db = ensureDB()
    db.checkOtherItems = AP.Settings.checkOtherItems
    db.sameStats = AP.Settings.sameStats
end

AP.Format = {}

function AP.Format.Money(copper)
    if not copper or copper <= 0 then
        return "0g"
    end
    return Auctionator.Utilities.CreatePaddedMoneyString(copper)
end
