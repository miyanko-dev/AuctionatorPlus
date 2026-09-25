local _, AP = ...

-- Forever half of the Full Scan buttons: Auctionator's ModernAH layout, on the shopping tab's Export Results row and under the selling tab's prices inset

-- Bottom-left of the results inset, on the Export Results row. Parented to that button so it hides with it whenever a buy screen covers the results
local function ensureShoppingButton()
    if AP.shoppingScanButton then return true end
    local shoppingFrame = AuctionatorShoppingFrame
    local inset = shoppingFrame and shoppingFrame.ShoppingResultsInset
    local exportButton = shoppingFrame and shoppingFrame.ExportCSV
    if not inset or not exportButton then return false end

    local button = AP.FullScanButton.Create("AuctionatorPlusFullScanShoppingButton", exportButton)
    button:SetPoint("LEFT", inset, "LEFT", 0, 0)
    button:SetPoint("BOTTOM", exportButton, "BOTTOM", 0, 0)
    AP.shoppingScanButton = button
    return true
end

-- Bottom-right of the selling tab, under the prices inset on the row the price mini-tabs use
local function ensureSellingButton()
    if AP.sellingScanButton then return true end
    local sellingFrame = AuctionatorSellingFrame
    local inset = sellingFrame and sellingFrame.HistoricalPriceInset
    if not inset then return false end

    local button = AP.FullScanButton.Create("AuctionatorPlusFullScanSellingButton", sellingFrame)
    button:SetPoint("TOPRIGHT", inset, "BOTTOMRIGHT", 0, -2)
    AP.sellingScanButton = button
    return true
end

function AP.FullScanButton.Ensure()
    local shoppingReady = ensureShoppingButton()
    local sellingReady = ensureSellingButton()
    return shoppingReady and sellingReady
end
