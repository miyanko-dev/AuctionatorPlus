local _, AP = ...

-- Full Scan buttons with a live progress label for either scan mode, on the shopping tab's Export Results row and under the selling tab's prices inset, as AP.shoppingScanButton and AP.sellingScanButton
AP.FullScanButton = {}

local BUTTON_LABEL = "Full Scan"
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

-- Both scan modes report the same four steps under their own event names; Auctionator's own scan status listens to both sets the same way
local SCAN_STEPS = { "ScanStart", "ScanProgress", "ScanComplete", "ScanFailed" }
local stepOf, scanEvents = {}, {}
for _, events in ipairs({ Auctionator.FullScan.Events, Auctionator.IncrementalScan.Events }) do
    for _, step in ipairs(SCAN_STEPS) do
        stepOf[events[step]] = step
        scanEvents[#scanEvents + 1] = events[step]
    end
end

AP.Bridge.Listen(scanEvents, function(_, eventName, eventData)
    local step = stepOf[eventName]
    if step == "ScanStart" then
        scanActive = true
        showProgress(0)
    elseif step == "ScanProgress" then
        if not scanActive then return end
        local pct = math.floor((eventData or 0) * 100)
        if pct >= 100 then
            showFinal(100, GREEN_FONT_COLOR)
        else
            showProgress(pct)
        end
    elseif step == "ScanComplete" then
        showFinal(100, GREEN_FONT_COLOR)
    elseif step == "ScanFailed" then
        showFinal(lastPct, RED_FONT_COLOR)
    end
end)

-- The incremental scan and a shopping search would page the client's one browse result set at once; Auctionator's own button never meets a running search, since leaving the Shopping tab stops it
local function shoppingSearchRunning()
    local shoppingFrame = AuctionatorShoppingFrame
    return shoppingFrame ~= nil and shoppingFrame.searchRunning == true
end

local function start()
    if shoppingSearchRunning() then return end
    AP.Bridge.StartFullScan()
end

-- Only the replicate scan has a cooldown, so that line shows only while its mode is on
local function addStateLines(tooltip)
    if AP.Bridge.IsReplicateScan() then
        GameTooltip_AddNormalLine(tooltip, "Alternate Scan Mode is on: one scan every 15 minutes.", true)
    end
    if shoppingSearchRunning() then
        GameTooltip_AddErrorLine(tooltip, "Wait for the shopping search to finish first.", true)
    end
end

-- One Full Scan button, painted with the running scan's label; the caller anchors it
local function createButton(name, parent)
    local button = AP.Panel.CreateTabButton(name, parent, BUTTON_LABEL, "Auctionator Full Scan",
        "Runs Auctionator's full auction-house scan in the scan mode set in Auctionator's options, like Auctionator's own Full Scan button. Needs no shopping search running.",
        addStateLines)
    paintButton(button, lastText)
    button:SetScript("OnClick", start)
    return button
end

-- Bottom-left of the results inset, on the Export Results row. Parented to that button so it hides with it whenever a buy screen covers the results
local function ensureShoppingButton()
    if AP.shoppingScanButton then return true end
    local shoppingFrame = AuctionatorShoppingFrame
    local inset = shoppingFrame and shoppingFrame.ShoppingResultsInset
    local exportButton = shoppingFrame and shoppingFrame.ExportCSV
    if not inset or not exportButton then return false end

    local button = createButton("AuctionatorPlusFullScanShoppingButton", exportButton)
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

    local button = createButton("AuctionatorPlusFullScanSellingButton", sellingFrame)
    button:SetPoint("TOPRIGHT", inset, "BOTTOMRIGHT", 0, -2)
    AP.sellingScanButton = button
    return true
end

function AP.FullScanButton.Ensure()
    local shoppingReady = ensureShoppingButton()
    local sellingReady = ensureSellingButton()
    return shoppingReady and sellingReady
end
