local _, AP = ...


-- Seeded into AuctionatorPlusDB by the settings panel, which also uses the keys as its variable keys
AP.Defaults = {
    sellThresholdPct = 15,
    glowRequireBoth = true,
    levelTolerance = 2,
    dpsTolerancePct = 20,
    statValueTolerance = 30,
    statCountTolerance = 0,
    minSaleRate = 0,
    guideAtLogin = true,
}

-- Account-wide store for the settings, the shopping stat filter and the per-character guide flags
function AP.DB()
    if type(AuctionatorPlusDB) ~= "table" then
        AuctionatorPlusDB = {}
    end
    return AuctionatorPlusDB
end
