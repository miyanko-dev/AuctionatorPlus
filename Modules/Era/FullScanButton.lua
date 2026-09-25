local _, AP = ...

-- Era half of the Full Scan buttons: Auctionator's legacy layout, bottom-left of the shopping results and at the left of the selling tab's current-prices row
local BUTTON_GAP = 2

local buyFrameHooked = false

-- Pack History, Refresh, Buy and Cancel to the right so the Full Scan button fits at the row's left
local function packBottomRow(buyFrame)
    if buyFrame.apRowPacked then return end
    local history = buyFrame.HistoryButton
    local currentPrices = buyFrame.CurrentPrices
    local refresh, buy, cancel = currentPrices.RefreshButton, currentPrices.BuyButton, currentPrices.CancelButton
    if not history or not refresh or not buy or not cancel then return end

    buy:SetPoint("BOTTOMRIGHT", cancel, "BOTTOMLEFT", -BUTTON_GAP, 0)
    refresh:SetPoint("BOTTOMRIGHT", buy, "BOTTOMLEFT", -BUTTON_GAP, 0)
    history:ClearAllPoints()
    history:SetPoint("BOTTOMRIGHT", refresh, "BOTTOMLEFT", -BUTTON_GAP, 0)
    buyFrame.apRowPacked = true
end

-- Above the host's own art, from the left edge of leftRegion on the row of bottomRegion
local function place(button, parent, leftRegion, bottomRegion)
    button:SetFrameStrata(parent:GetFrameStrata())
    button:SetFrameLevel(parent:GetFrameLevel() + 5)
    button:ClearAllPoints()
    button:SetPoint("LEFT", leftRegion, "LEFT", 0, 0)
    button:SetPoint("BOTTOM", bottomRegion, "BOTTOM", 0, 0)
end

local function ensureShoppingButton()
    if AP.shoppingScanButton then return true end
    local shoppingFrame = AuctionatorShoppingFrame
    local inset = shoppingFrame and shoppingFrame.ShoppingResultsInset
    local background = inset and inset.Bg
    local exportButton = shoppingFrame and shoppingFrame.ExportCSV
    if not background or not exportButton then return false end

    local button = AP.FullScanButton.Create("AuctionatorPlusFullScanShoppingButton", shoppingFrame)
    place(button, shoppingFrame, background, exportButton)
    AP.shoppingScanButton = button
    return true
end

local function ensureSellingButton()
    if AP.sellingScanButton then return true end
    local sellingFrame = AuctionatorSellingFrame
    local buyFrame = sellingFrame and sellingFrame.BuyFrame
    local currentPrices = buyFrame and buyFrame.CurrentPrices
    local background = currentPrices and currentPrices.Inset and currentPrices.Inset.Bg
    local refresh = currentPrices and currentPrices.RefreshButton
    local history = buyFrame and buyFrame.HistoryButton
    if not background or not refresh or not history then return false end

    packBottomRow(buyFrame)
    local button = AP.FullScanButton.Create("AuctionatorPlusFullScanSellingButton", buyFrame)
    place(button, buyFrame, background, refresh)
    button:SetPoint("RIGHT", history, "LEFT", -BUTTON_GAP, 0)
    AP.sellingScanButton = button
    return true
end

-- The shopping button sits over the results inset the buy screen covers, so it hides while that screen shows
local function syncShoppingButton()
    local buyFrame = AuctionatorBuyFrame
    AP.shoppingScanButton:SetShown(not (buyFrame and buyFrame:IsShown()))
end

local function hookBuyFrame()
    if buyFrameHooked then return true end
    local buyFrame = AuctionatorBuyFrame
    if not AP.shoppingScanButton or not buyFrame then return false end

    buyFrame:HookScript("OnShow", syncShoppingButton)
    buyFrame:HookScript("OnHide", syncShoppingButton)
    AuctionatorShoppingFrame:HookScript("OnShow", syncShoppingButton)
    syncShoppingButton()
    buyFrameHooked = true
    return true
end

function AP.FullScanButton.Ensure()
    local shoppingReady = ensureShoppingButton()
    local sellingReady = ensureSellingButton()
    local buyFrameReady = hookBuyFrame()
    return shoppingReady and sellingReady and buyFrameReady
end
