local _, AP = ...

AP.Constants = {
    CallerID = "AuctionatorPlus",

    HistoryWindowDays = 14,  -- keeps the local average comparable to TSM's 14-day market value
}

-- Persist options in AuctionatorPlusDB; loaded on PLAYER_LOGIN.
AP.Settings = {
    showSimilarItems = false,
    showSimilarBags = false,
}

local function ensureDB()
    if type(AuctionatorPlusDB) ~= "table" then
        AuctionatorPlusDB = {}
    end
    return AuctionatorPlusDB
end

function AP.LoadSettings()
    local db = ensureDB()
    if type(db.showSimilarItems) == "boolean" then
        AP.Settings.showSimilarItems = db.showSimilarItems
    end
    if type(db.showSimilarBags) == "boolean" then
        AP.Settings.showSimilarBags = db.showSimilarBags
    end
end

function AP.SaveSettings()
    local db = ensureDB()
    db.showSimilarItems = AP.Settings.showSimilarItems
    db.showSimilarBags = AP.Settings.showSimilarBags
end

AP.Format = {}

function AP.Format.Money(copper)
    if not copper or copper <= 0 then
        return "0g"
    end
    return Auctionator.Utilities.CreatePaddedMoneyString(copper)
end
