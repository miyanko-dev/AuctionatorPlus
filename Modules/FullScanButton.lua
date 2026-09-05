local _, AP = ...

AP.FullScanButton = {}

local BUTTON_LABEL = "Full Scan"
local BUTTON_WIDTH = 110
local BUTTON_HEIGHT = 22
local BUTTON_GAP = 2
local TOOLTIP_GAP = 4
local FINAL_HOLD_SECONDS = 2
local FADE_DURATION = 0.2

local COLOR_WHITE = { 1, 1, 1 }
local COLOR_GREEN = { 0.1, 1, 0.1 }
local COLOR_RED = { 1, 0.2, 0.2 }

local progressTooltip
local hideTimer
local scanActive = false

-- Last readout, kept while a scan runs or its verdict is held so a button re-shown mid-scan can repaint it
local lastText, lastColor

local function onClick()
    local scanFrame = Auctionator.State.FullScanFrameRef
    if scanFrame then scanFrame:InitiateScan() end
end

-- The readout follows whichever Full Scan button is on screen
local function activeButton()
    local shop, sell = AP.shoppingScanButton, AP.sellingScanButton
    if shop and shop:IsVisible() then return shop end
    if sell and sell:IsVisible() then return sell end
    return nil
end

local function ensureTooltip()
    if not progressTooltip then
        progressTooltip = CreateFrame("GameTooltip", "AuctionatorPlusScanProgressTooltip", UIParent, "GameTooltipTemplate")
    end
    return progressTooltip
end

local function hideTooltip()
    local tt = progressTooltip
    if not tt or not tt:IsShown() then return end
    UIFrameFadeRemoveFrame(tt)
    UIFrameFade(tt, {
        mode = "OUT",
        timeToFade = FADE_DURATION,
        startAlpha = tt:GetAlpha(),
        finishedFunc = function() tt:Hide() end,
    })
end

-- Paint text above a button; fade in when it appears, swap the text in place while it is already visible
local function paintProgress(button, text, color)
    if not button then return end
    local tt = ensureTooltip()
    if tt:GetOwner() ~= button then
        tt:SetOwner(button, "ANCHOR_NONE")
        tt:ClearAllPoints()
        tt:SetPoint("BOTTOM", button, "TOP", 0, TOOLTIP_GAP)
    end
    tt:SetMinimumWidth(button:GetWidth())
    tt:SetText(text, unpack(color))
    if tt:IsShown() and not UIFrameIsFading(tt) then
        tt:SetAlpha(1)
        return
    end
    UIFrameFadeRemoveFrame(tt)
    UIFrameFadeIn(tt, FADE_DURATION, tt:IsShown() and tt:GetAlpha() or 0, 1)
end

local function cancelHideTimer()
    if hideTimer then
        hideTimer:Cancel()
        hideTimer = nil
    end
end

local function showProgress(text, color)
    cancelHideTimer()
    lastText, lastColor = text, color
    paintProgress(activeButton(), text, color)
end

-- Hold the verdict briefly, then fade the readout away
local function showFinal(text, color)
    scanActive = false
    showProgress(text, color)
    hideTimer = C_Timer.NewTimer(FINAL_HOLD_SECONDS, function()
        hideTimer = nil
        lastText, lastColor = nil, nil
        hideTooltip()
    end)
end

local scanEvents = Auctionator.FullScan.Events

AP.Bridge.Listen({
    scanEvents.ScanStart,
    scanEvents.ScanProgress,
    scanEvents.ScanComplete,
    scanEvents.ScanFailed,
}, function(_, eventName, eventData)
    if eventName == scanEvents.ScanStart then
        scanActive = true
        showProgress("0%", COLOR_WHITE)
    elseif eventName == scanEvents.ScanProgress then
        if not scanActive then return end
        local pct = math.floor((eventData or 0) * 100)
        if pct >= 100 then
            showFinal("Completed", COLOR_GREEN)
        else
            showProgress(pct .. "%", COLOR_WHITE)
        end
    elseif eventName == scanEvents.ScanComplete then
        showFinal("Completed", COLOR_GREEN)
    elseif eventName == scanEvents.ScanFailed then
        showFinal("Cancelled", COLOR_RED)
    end
end)

-- Pack History, Refresh, Buy and Cancel to the right so the Full Scan button fits at the row's left
local function packBottomRow(buyFrame)
    if buyFrame.apRowPacked then return end
    local history = buyFrame.HistoryButton
    local cp = buyFrame.CurrentPrices
    local refresh, buy, cancel = cp.RefreshButton, cp.BuyButton, cp.CancelButton
    if not history or not refresh or not buy or not cancel then return end

    buy:SetPoint("BOTTOMRIGHT", cancel, "BOTTOMLEFT", -BUTTON_GAP, 0)
    refresh:SetPoint("BOTTOMRIGHT", buy, "BOTTOMLEFT", -BUTTON_GAP, 0)
    history:ClearAllPoints()
    history:SetPoint("BOTTOMRIGHT", refresh, "BOTTOMLEFT", -BUTTON_GAP, 0)
    buyFrame.apRowPacked = true
end

local function createButton(name, parent, leftRegion, bottomRegion)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    button:SetText(BUTTON_LABEL)
    button:SetFrameStrata(parent:GetFrameStrata())
    button:SetFrameLevel(parent:GetFrameLevel() + 5)
    button:ClearAllPoints()
    button:SetPoint("LEFT", leftRegion, "LEFT", 0, 0)
    button:SetPoint("BOTTOM", bottomRegion, "BOTTOM", 0, 0)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self)
        if lastText then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Auctionator Full Scan")
        GameTooltip:AddLine("Runs the Auctionator full auction-house scan. Available once every 15 minutes.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnShow", function(self)
        if lastText then paintProgress(self, lastText, lastColor) end
    end)
    button:SetScript("OnHide", hideTooltip)
    return button
end

local function ensureShoppingButton()
    if AP.shoppingScanButton then return true end
    local shoppingFrame = _G.AuctionatorShoppingFrame
    local inset = shoppingFrame and shoppingFrame.ShoppingResultsInset
    local bg = inset and inset.Bg
    local exportButton = shoppingFrame and shoppingFrame.ExportCSV
    if not bg or not exportButton then return false end
    AP.shoppingScanButton = createButton("AuctionatorPlusFullScanShoppingButton", shoppingFrame, bg, exportButton)
    return true
end

local function ensureSellingButton()
    if AP.sellingScanButton then return true end
    local sellingFrame = _G.AuctionatorSellingFrame
    local buyFrame = sellingFrame and sellingFrame.BuyFrame
    local currentPrices = buyFrame and buyFrame.CurrentPrices
    local inset = currentPrices and currentPrices.Inset
    local bg = inset and inset.Bg
    local refresh = currentPrices and currentPrices.RefreshButton
    local history = buyFrame and buyFrame.HistoryButton
    if not bg or not refresh or not history then return false end
    packBottomRow(buyFrame)
    local button = createButton("AuctionatorPlusFullScanSellingButton", buyFrame, bg, refresh)
    button:SetPoint("RIGHT", history, "LEFT", -BUTTON_GAP, 0)
    AP.sellingScanButton = button
    return true
end

function AP.FullScanButton.Ensure()
    local shoppingReady = ensureShoppingButton()
    local sellingReady = ensureSellingButton()
    return shoppingReady and sellingReady
end
