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
local lastText, lastColor
local tooltipShown = false
local fadeDriver = CreateFrame("Frame")

local function scanReady()
    return Auctionator.State.FullScanFrameRef ~= nil
end

local function onClick()
    if not scanReady() then return end
    Auctionator.State.FullScanFrameRef:InitiateScan()
end

local function activeButton()
    local shop = AP.fullScanShoppingButton
    local sell = AP.fullScanSellingButton
    if shop and shop:IsVisible() then return shop end
    if sell and sell:IsVisible() then return sell end
    return nil
end

local function ensureProgressTooltip()
    if progressTooltip then return progressTooltip end
    progressTooltip = CreateFrame(
        "GameTooltip", "AuctionatorPlusScanProgressTooltip", UIParent, "GameTooltipTemplate")
    return progressTooltip
end

local function stopFade()
    fadeDriver:SetScript("OnUpdate", nil)
end

local function startFade(tt, fromAlpha, toAlpha, onComplete)
    stopFade()
    tt:SetAlpha(fromAlpha)
    tt:Show()
    fadeDriver.tt = tt
    fadeDriver.from = fromAlpha
    fadeDriver.to = toAlpha
    fadeDriver.elapsed = 0
    fadeDriver.onComplete = onComplete
    fadeDriver:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        local progress = math.min(1, self.elapsed / FADE_DURATION)
        self.tt:SetAlpha(self.from + (self.to - self.from) * progress)
        if progress >= 1 then
            self:SetScript("OnUpdate", nil)
            local cb = self.onComplete
            self.onComplete = nil
            if cb then cb() end
        end
    end)
end

local function hideProgressTooltip()
    if not progressTooltip or not tooltipShown then
        if progressTooltip then progressTooltip:Hide() end
        tooltipShown = false
        return
    end
    tooltipShown = false
    local tt = progressTooltip
    startFade(tt, tt:GetAlpha(), 0, function() tt:Hide() end)
end

local function cancelHideTimer()
    if hideTimer then
        hideTimer:Cancel()
        hideTimer = nil
    end
end

local function applyTooltipWidth(tt, button)
    local width = button:GetWidth()
    if width and width > 0 then
        tt:SetMinimumWidth(width)
    end
end

local function showProgressOnButton(button, text, color)
    if not button then return end
    local tt = ensureProgressTooltip()
    if tt:GetOwner() ~= button then
        tt:SetOwner(button, "ANCHOR_NONE")
        tt:ClearAllPoints()
        tt:SetPoint("BOTTOM", button, "TOP", 0, TOOLTIP_GAP)
    end
    applyTooltipWidth(tt, button)
    tt:SetText(text, color[1], color[2], color[3])
    if not tooltipShown then
        tooltipShown = true
        startFade(tt, 0, 1, nil)
    else
        stopFade()
        tt:SetAlpha(1)
        tt:Show()
    end
end

local function showProgress(text, color)
    cancelHideTimer()
    lastText = text
    lastColor = color
    showProgressOnButton(activeButton(), text, color)
end

local function showFinalThenHide(text, color)
    cancelHideTimer()
    scanActive = false
    lastText = text
    lastColor = color
    showProgressOnButton(activeButton(), text, color)
    hideTimer = C_Timer.NewTimer(FINAL_HOLD_SECONDS, function()
        hideTimer = nil
        lastText = nil
        lastColor = nil
        hideProgressTooltip()
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
            showFinalThenHide("Completed", COLOR_GREEN)
        else
            showProgress(pct .. "%", COLOR_WHITE)
        end
    elseif eventName == scanEvents.ScanComplete then
        showFinalThenHide("Completed", COLOR_GREEN)
    elseif eventName == scanEvents.ScanFailed then
        showFinalThenHide("Cancelled", COLOR_RED)
    end
end)

local function repositionSellingBottomRow(buyFrame)
    if not buyFrame or buyFrame.auctionatorPlusBottomRowMoved then return end
    local history = buyFrame.HistoryButton
    local cp = buyFrame.CurrentPrices
    local refresh = cp and cp.RefreshButton
    local buy = cp and cp.BuyButton
    local cancel = cp and cp.CancelButton
    if not history or not refresh or not buy or not cancel then return end

    buy:SetPoint("BOTTOMRIGHT", cancel, "BOTTOMLEFT", -BUTTON_GAP, 0)
    refresh:SetPoint("BOTTOMRIGHT", buy, "BOTTOMLEFT", -BUTTON_GAP, 0)
    history:ClearAllPoints()
    history:SetPoint("BOTTOMRIGHT", refresh, "BOTTOMLEFT", -BUTTON_GAP, 0)

    buyFrame.auctionatorPlusBottomRowMoved = true
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
        if scanActive or hideTimer then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Auctionator Full Scan")
        GameTooltip:AddLine(
            "Runs the Auctionator full auction-house scan. Available once every 15 minutes.",
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnShow", function(self)
        if (scanActive or hideTimer) and lastText and lastColor then
            showProgressOnButton(self, lastText, lastColor)
        end
    end)
    button:SetScript("OnHide", hideProgressTooltip)
    return button
end

local function ensureShoppingButton()
    if AP.fullScanShoppingButton then return true end
    local shoppingFrame = _G.AuctionatorShoppingFrame
    local inset = shoppingFrame and shoppingFrame.ShoppingResultsInset
    local bg = inset and inset.Bg
    local exportButton = shoppingFrame and shoppingFrame.ExportCSV
    if not shoppingFrame or not bg or not exportButton then return false end
    AP.fullScanShoppingButton = createButton(
        "AuctionatorPlusFullScanShoppingButton", shoppingFrame, bg, exportButton)
    return true
end

local function ensureSellingButton()
    if AP.fullScanSellingButton then return true end
    local sellingFrame = _G.AuctionatorSellingFrame
    local buyFrame = sellingFrame and sellingFrame.BuyFrame
    local currentPrices = buyFrame and buyFrame.CurrentPrices
    local inset = currentPrices and currentPrices.Inset
    local bg = inset and inset.Bg
    local refresh = currentPrices and currentPrices.RefreshButton
    local history = buyFrame and buyFrame.HistoryButton
    if not buyFrame or not bg or not refresh or not history then return false end
    repositionSellingBottomRow(buyFrame)
    local btn = createButton(
        "AuctionatorPlusFullScanSellingButton", buyFrame, bg, refresh)
    btn:SetPoint("RIGHT", history, "LEFT", -BUTTON_GAP, 0)
    AP.fullScanSellingButton = btn
    return true
end

function AP.FullScanButton.Ensure()
    local shoppingReady = ensureShoppingButton()
    local sellingReady = ensureSellingButton()
    return shoppingReady and sellingReady
end
