local _, AP = ...

-- Each returns true once its UI piece exists, the first three from the loaded client's half; order matters where one button anchors to another
local ENSURES = {
    AP.FullScanButton.Ensure,
    AP.SimilarItems.Ensure,
    AP.SaleScan.Ensure,
    AP.ShoppingFilter.Ensure,
    AP.SettingsPanel.EnsureButton,
}

-- Retry until every piece is in place; Auctionator creates the host frames on or shortly after the first AH open
local function ensureButtons(attempt)
    local ready = true
    for _, ensure in ipairs(ENSURES) do
        if not ensure() then ready = false end
    end
    if ready or attempt > 20 then return end
    C_Timer.After(0.5, function() ensureButtons(attempt + 1) end)
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:RegisterEvent("AUCTION_HOUSE_SHOW")
bootstrap:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        AP.SettingsPanel.Register()
        AP.Guide.ShowOnce()
    elseif event == "AUCTION_HOUSE_SHOW" then
        ensureButtons(1)
    end
end)
