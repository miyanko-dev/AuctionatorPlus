local _, AP = ...

-- Quick guide: what Auctionator Plus adds and how to enable the TSM features; shown once per character at login while the toggle is on, reopenable from the options page
AP.Guide = {}

local WIDTH = 440

local SECTIONS = {
    { "Tooltips", "Every item shows its Average Price from Auctionator (14 days of your scans) and from TSM, each with its data age, then the Relative Value of the last known price against each: how far above or below the average it sits. Green is favourable for the view you are in." },
    { "Shopping", "Results gain Relative Value and Sale Rate columns; the Relative Value uses the Auctionator average, or the mean of both when TSM data exists. Filter narrows equipment to chosen stats. Full Scan runs Auctionator's full scan." },
    { "Selling", "Show Similar Items or Bags lists comparable auctions: same slot and type, with level, stat amounts and stat count within the set ranges. Click one to take its price. Bag items glow green when their Relative Value reaches the sell threshold. Sale Scan refreshes bag prices." },
    { "TSM features", "Market value and sale rate come from the TSM desktop app:\n1. Install TradeSkillMaster and TradeSkillMaster_AppHelper.\n2. Run the TSM desktop app, pointed at this WoW folder.\n3. Log in once with TSM enabled on every realm and faction you trade on.\nData loads at login; /reload after the app syncs." },
}

local frame

local function build()
    frame = AP.Panel.Create("AuctionatorPlusGuideFrame", "Auctionator Plus", WIDTH)
    for _, section in ipairs(SECTIONS) do
        AP.Panel.AddSection(frame, section[1], section[2])
    end
    AP.Panel.AddButton(frame, "Auctionator Plus Options", AP.SettingsPanel.Open)
    AP.Panel.Fit(frame)
end

function AP.Guide.Show()
    if not frame then build() end
    frame:Show()
end

-- Once per character, while the login toggle is on
function AP.Guide.ShowOnce()
    local db = AP.DB()
    if not db.guideAtLogin then return end
    db.guideSeen = db.guideSeen or {}
    local character = UnitName("player") .. "-" .. GetRealmName()
    if db.guideSeen[character] then return end
    db.guideSeen[character] = true
    AP.Guide.Show()
end
