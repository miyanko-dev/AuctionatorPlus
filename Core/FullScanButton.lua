FF.FullScanButton = {}

local BUTTON_LABEL = "Full Scan"
local COMPLETE_LABEL = "Scan Complete"
local CANCELLED_LABEL = "Scan Cancelled"
local FLASH_DURATION = 2
local HORIZONTAL_PADDING = 14
local CLOSE_BUTTON_GAP = -120
local STATUS_GAP = 6
local MIN_BUTTON_WIDTH = 96
local BUTTON_HEIGHT = 22

local COLOR_WHITE = { 1, 1, 1 }
local COLOR_GREEN = { 0.1, 1, 0.1 }
local COLOR_RED = { 1, 0.2, 0.2 }

local function ApplyButtonWidth(button)
  local fs = button:GetFontString()
  local width = (fs and fs:GetStringWidth()) or 0
  button:SetWidth(math.max(MIN_BUTTON_WIDTH, math.ceil(width + HORIZONTAL_PADDING * 2)))
end

local function SetStatus(button, text, color)
  local label = button._statusLabel
  if not label then return end
  if button._statusTimer then
    button._statusTimer:Cancel()
    button._statusTimer = nil
  end
  if not text or text == "" then
    label:SetText("")
    label:Hide()
    return
  end
  label:SetTextColor(color[1], color[2], color[3])
  label:SetText(text)
  label:Show()
end

local function FlashStatus(button, text, color)
  SetStatus(button, text, color)
  button._statusTimer = C_Timer.NewTimer(FLASH_DURATION, function()
    button._statusTimer = nil
    SetStatus(button, nil)
  end)
end

local function FullScanReady()
  return Auctionator and Auctionator.State and Auctionator.State.FullScanFrameRef ~= nil
end

local function OnClick(self)
  if not FullScanReady() then return end
  Auctionator.State.FullScanFrameRef:InitiateScan()
end

local function ReceiveEvent(self, eventName, eventData)
  local events = Auctionator and Auctionator.FullScan and Auctionator.FullScan.Events
  if not events then return end

  if eventName == events.ScanStart then
    SetStatus(self, "0%", COLOR_WHITE)
  elseif eventName == events.ScanProgress then
    local pct = math.floor((eventData or 0) * 100)
    SetStatus(self, pct .. "%", COLOR_WHITE)
  elseif eventName == events.ScanComplete then
    FlashStatus(self, COMPLETE_LABEL, COLOR_GREEN)
  elseif eventName == events.ScanFailed then
    FlashStatus(self, CANCELLED_LABEL, COLOR_RED)
  end
end

local function RegisterEvents(button)
  if button._fsEventsRegistered then return end
  if not (Auctionator and Auctionator.EventBus and Auctionator.FullScan and Auctionator.FullScan.Events) then
    return
  end
  button._fsEventsRegistered = true
  button.ReceiveEvent = ReceiveEvent

  Auctionator.EventBus:Register(button, {
    Auctionator.FullScan.Events.ScanStart,
    Auctionator.FullScan.Events.ScanProgress,
    Auctionator.FullScan.Events.ScanComplete,
    Auctionator.FullScan.Events.ScanFailed,
  })
end

function FF.FullScanButton.Ensure()
  if FF.fullScanButton then
    RegisterEvents(FF.fullScanButton)
    return true
  end

  local ahFrame = FF.Adapter and FF.Adapter.GetAHFrame and FF.Adapter.GetAHFrame()
  if not ahFrame then return false end

  local closeButton = (ahFrame and ahFrame.CloseButton) or _G.AuctionFrameCloseButton
  if not closeButton then return false end

  local button = CreateFrame("Button", "AuctionatorPlusFullScanButton", ahFrame, "UIPanelButtonTemplate")
  button:SetHeight(BUTTON_HEIGHT)
  button:SetPoint("RIGHT", closeButton, "LEFT", CLOSE_BUTTON_GAP, 0)
  button:SetFrameStrata(ahFrame:GetFrameStrata())
  button:SetFrameLevel(ahFrame:GetFrameLevel() + 5)
  button:SetText(BUTTON_LABEL)
  ApplyButtonWidth(button)
  button:SetScript("OnClick", OnClick)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Auctionator Full Scan")
    GameTooltip:AddLine(
      "Runs the Auctionator full auction-house scan. Available once every 15 minutes.",
      1, 1, 1, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", GameTooltip_Hide)

  local status = button:CreateFontString(nil, "OVERLAY", "GameFontNormalOutline")
  status:SetPoint("LEFT", button, "RIGHT", STATUS_GAP, 0)
  status:SetTextColor(1, 1, 1)
  status:Hide()
  button._statusLabel = status

  button:Show()

  FF.fullScanButton = button
  RegisterEvents(button)
  return true
end
