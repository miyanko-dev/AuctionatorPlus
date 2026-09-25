local _, AP = ...

-- Full Scan buttons on the shopping and selling tabs with a live progress label; each client's half places them in its own Auctionator layout as AP.shoppingScanButton and AP.sellingScanButton
AP.FullScanButton = {}

local BUTTON_LABEL = "Full Scan"
local BUTTON_WIDTH = 110
local BUTTON_HEIGHT = 22
local FINAL_HOLD_SECONDS = 2
local FADE_DURATION = 0.3

local hideTimer
local scanActive = false
local lastPct = 0

-- Current label, nil while idle, so a button created mid-scan can paint itself
local lastText

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
    return color and color:WrapTextInColorCode(text) or text
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

-- Both Auctionator builds fire the same four scan events, under different names
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
            showFinal(100, GREEN_FONT_COLOR)
        else
            showProgress(pct)
        end
    elseif eventName == scanEvents.ScanComplete then
        showFinal(100, GREEN_FONT_COLOR)
    elseif eventName == scanEvents.ScanFailed then
        showFinal(lastPct, RED_FONT_COLOR)
    end
end)

-- One Full Scan button in Auctionator's own button metrics; the caller anchors it
function AP.FullScanButton.Create(name, parent)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    paintButton(button, lastText)
    button:SetScript("OnClick", AP.Bridge.StartFullScan)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip_SetTitle(GameTooltip, "Auctionator Full Scan")
        GameTooltip_AddHighlightLine(GameTooltip, "Runs the Auctionator full auction-house scan. Available once every 15 minutes.", true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end
