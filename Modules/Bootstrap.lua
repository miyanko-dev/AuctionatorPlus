local _, AP = ...

-- Hide the full-scan shopping button while the buy screen covers the results inset it sits over.
local function setFullScanButtonShown(shown)
    if AP.fullScanShoppingButton then
        if shown then AP.fullScanShoppingButton:Show() else AP.fullScanShoppingButton:Hide() end
    end
end

local function syncFullScanButtonVisibility()
    local buyFrame = _G.AuctionatorBuyFrame
    setFullScanButtonShown(not (buyFrame and buyFrame:IsShown()))
end

local function hookBuyFrameVisibility()
    if AP.buyFrameHooked then return true end
    if not AP.fullScanShoppingButton then return false end

    local buyFrame = _G.AuctionatorBuyFrame
    if not buyFrame then return false end

    buyFrame:HookScript("OnShow", function() setFullScanButtonShown(false) end)
    buyFrame:HookScript("OnHide", function() setFullScanButtonShown(true) end)

    local shoppingFrame = _G.AuctionatorShoppingFrame
    if shoppingFrame then
        shoppingFrame:HookScript("OnShow", syncFullScanButtonVisibility)
    end

    syncFullScanButtonVisibility()

    AP.buyFrameHooked = true
    return true
end

-- Retry until every piece is in place; Auctionator creates the host frames on or shortly after first AH open.
local function ensureButtons(attempt)
    attempt = attempt or 1
    local fullScanReady = AP.FullScanButton.Ensure()
    local buyHooked = fullScanReady and hookBuyFrameVisibility()
    local watchReady = AP.SellingWatch.Ensure()
    local saleScanReady = AP.SaleScan.Ensure()
    local filterReady = AP.ShoppingFilter.Ensure()
    if (fullScanReady and buyHooked and watchReady and saleScanReady and filterReady) or attempt > 20 then return end
    C_Timer.After(0.5, function() ensureButtons(attempt + 1) end)
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:RegisterEvent("AUCTION_HOUSE_SHOW")
bootstrap:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        AP.LoadSettings()
        AP.SellingWatch.Ensure()

    elseif event == "AUCTION_HOUSE_SHOW" then
        ensureButtons()
    end
end)
