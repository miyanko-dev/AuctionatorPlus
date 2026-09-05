local _, AP = ...

local buyFrameHooked = false

-- The shopping full-scan button sits over the results inset the buy screen covers, so it hides while that screen shows
local function syncScanButton()
    local buyFrame = _G.AuctionatorBuyFrame
    AP.shoppingScanButton:SetShown(not (buyFrame and buyFrame:IsShown()))
end

local function hookBuyFrame()
    if buyFrameHooked then return true end
    local buyFrame = _G.AuctionatorBuyFrame
    if not AP.shoppingScanButton or not buyFrame then return false end

    buyFrame:HookScript("OnShow", syncScanButton)
    buyFrame:HookScript("OnHide", syncScanButton)
    _G.AuctionatorShoppingFrame:HookScript("OnShow", syncScanButton)
    syncScanButton()
    buyFrameHooked = true
    return true
end

-- Each returns true once its UI piece exists; order matters where one button anchors to another
local ENSURES = {
    AP.FullScanButton.Ensure,
    hookBuyFrame,
    AP.SellingWatch.Ensure,
    AP.SaleScan.Ensure,
    AP.ShoppingFilter.Ensure,
    AP.SettingsPanel.EnsureButton,
}

-- Retry until every piece is in place; Auctionator creates the host frames on or shortly after first AH open
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
