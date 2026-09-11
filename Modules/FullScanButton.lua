local _, AP = ...

AP.FullScanButton = {}

local BUTTON_LABEL = "Full Scan"
local BUTTON_WIDTH = 110
local BUTTON_HEIGHT = 22
local BUTTON_GAP = 2
local FINAL_HOLD_SECONDS = 2
local FADE_DURATION = 0.3

local COLOR_GREEN = "|cff19ff19"
local COLOR_RED = "|cffff3333"

local hideTimer
local scanActive = false
local lastPct = 0

-- Current label, nil while idle, so a button created mid-scan can paint itself
local lastText

local function onClick()
    local scanFrame = Auctionator.State.FullScanFrameRef
    if scanFrame then scanFrame:InitiateScan() end
end

local function eachButton(fn)
    if AP.shoppingScanButton then fn(AP.shoppingScanButton) end
    if AP.sellingScanButton then fn(AP.sellingScanButton) end
end

-- Interrupt any running fade so a fresh scan never paints into a half-faded label
local function paintButton(button, text)
    local label = button:GetFontString()
    UIFrameFadeRemoveFrame(label)
    label:SetAlpha(1)
    button:SetText(text or BUTTON_LABEL)
end

-- Fade the verdict out, then fade the idle label back in
local function fadeToIdle(button)
    local label = button:GetFontString()
    UIFrameFadeRemoveFrame(label)
    UIFrameFade(label, {
        mode = "OUT",
        timeToFade = FADE_DURATION,
        startAlpha = label:GetAlpha(),
        endAlpha = 0,
        finishedFunc = function()
            button:SetText(BUTTON_LABEL)
            UIFrameFadeIn(label, FADE_DURATION, 0, 1)
        end,
    })
end

local function cancelHideTimer()
    if hideTimer then
        hideTimer:Cancel()
        hideTimer = nil
    end
end

local function progressText(pct, color)
    local text = BUTTON_LABEL .. " " .. pct .. "%"
    if color then return color .. text .. "|r" end
    return text
end

local function showProgress(pct)
    cancelHideTimer()
    lastPct = pct
    lastText = progressText(pct)
    eachButton(function(button) paintButton(button, lastText) end)
end

-- Hold the colored percentage briefly, then fade back to the idle label
local function showFinal(pct, color)
    scanActive = false
    cancelHideTimer()
    lastPct = pct
    lastText = progressText(pct, color)
    eachButton(function(button) paintButton(button, lastText) end)
    hideTimer = C_Timer.NewTimer(FINAL_HOLD_SECONDS, function()
        hideTimer = nil
        lastText = nil
        eachButton(fadeToIdle)
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
        showProgress(0)
    elseif eventName == scanEvents.ScanProgress then
        if not scanActive then return end
        local pct = math.floor((eventData or 0) * 100)
        if pct >= 100 then
            showFinal(100, COLOR_GREEN)
        else
            showProgress(pct)
        end
    elseif eventName == scanEvents.ScanComplete then
        showFinal(100, COLOR_GREEN)
    elseif eventName == scanEvents.ScanFailed then
        showFinal(lastPct, COLOR_RED)
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
    button:SetFrameStrata(parent:GetFrameStrata())
    button:SetFrameLevel(parent:GetFrameLevel() + 5)
    button:ClearAllPoints()
    button:SetPoint("LEFT", leftRegion, "LEFT", 0, 0)
    button:SetPoint("BOTTOM", bottomRegion, "BOTTOM", 0, 0)
    paintButton(button, lastText)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Auctionator Full Scan")
        GameTooltip:AddLine("Runs the Auctionator full auction-house scan. Available once every 15 minutes.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
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
