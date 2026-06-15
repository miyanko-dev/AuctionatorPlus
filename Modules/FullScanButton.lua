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

local function ScanReady()
  return Auctionator.State.FullScanFrameRef ~= nil
end

local function OnClick()
  if not ScanReady() then return end
  Auctionator.State.FullScanFrameRef:InitiateScan()
end

local function ActiveButton()
  local shop = AP.fullScanShoppingButton
  local sell = AP.fullScanSellingButton
  if shop and shop:IsVisible() then return shop end
  if sell and sell:IsVisible() then return sell end
  return nil
end

local function EnsureProgressTooltip()
  if progressTooltip then return progressTooltip end
  progressTooltip = CreateFrame(
    "GameTooltip", "AuctionatorPlusScanProgressTooltip", UIParent, "GameTooltipTemplate")
  return progressTooltip
end

local function StopFade()
  fadeDriver:SetScript("OnUpdate", nil)
end

local function StartFade(tt, fromAlpha, toAlpha, onComplete)
  StopFade()
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

local function HideProgressTooltip()
  if not progressTooltip or not tooltipShown then
    if progressTooltip then progressTooltip:Hide() end
    tooltipShown = false
    return
  end
  tooltipShown = false
  local tt = progressTooltip
  StartFade(tt, tt:GetAlpha(), 0, function() tt:Hide() end)
end

local function CancelHideTimer()
  if hideTimer then
    hideTimer:Cancel()
    hideTimer = nil
  end
end

local function ApplyTooltipWidth(tt, button)
  local width = button:GetWidth()
  if width and width > 0 then
    tt:SetMinimumWidth(width)
  end
end

local function ShowProgressOnButton(button, text, color)
  if not button then return end
  local tt = EnsureProgressTooltip()
  if tt:GetOwner() ~= button then
    tt:SetOwner(button, "ANCHOR_NONE")
    tt:ClearAllPoints()
    tt:SetPoint("BOTTOM", button, "TOP", 0, TOOLTIP_GAP)
  end
  ApplyTooltipWidth(tt, button)
  tt:SetText(text, color[1], color[2], color[3])
  if not tooltipShown then
    tooltipShown = true
    StartFade(tt, 0, 1, nil)
  else
    StopFade()
    tt:SetAlpha(1)
    tt:Show()
  end
end

local function ShowProgress(text, color)
  CancelHideTimer()
  lastText = text
  lastColor = color
  ShowProgressOnButton(ActiveButton(), text, color)
end

local function ShowFinalThenHide(text, color)
  CancelHideTimer()
  scanActive = false
  lastText = text
  lastColor = color
  ShowProgressOnButton(ActiveButton(), text, color)
  hideTimer = C_Timer.NewTimer(FINAL_HOLD_SECONDS, function()
    hideTimer = nil
    lastText = nil
    lastColor = nil
    HideProgressTooltip()
  end)
end

local ScanEvents = Auctionator.FullScan.Events

AP.Bridge.Listen({
  ScanEvents.ScanStart,
  ScanEvents.ScanProgress,
  ScanEvents.ScanComplete,
  ScanEvents.ScanFailed,
}, function(_, eventName, eventData)
  if eventName == ScanEvents.ScanStart then
    scanActive = true
    ShowProgress("0%", COLOR_WHITE)
  elseif eventName == ScanEvents.ScanProgress then
    if not scanActive then return end
    local pct = math.floor((eventData or 0) * 100)
    if pct >= 100 then
      ShowFinalThenHide("Completed", COLOR_GREEN)
    else
      ShowProgress(pct .. "%", COLOR_WHITE)
    end
  elseif eventName == ScanEvents.ScanComplete then
    ShowFinalThenHide("Completed", COLOR_GREEN)
  elseif eventName == ScanEvents.ScanFailed then
    ShowFinalThenHide("Cancelled", COLOR_RED)
  end
end)

local function RepositionSellingBottomRow(buyFrame)
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

local function CreateButton(name, parent, leftRegion, bottomRegion)
  local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
  button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
  button:SetText(BUTTON_LABEL)
  button:SetFrameStrata(parent:GetFrameStrata())
  button:SetFrameLevel(parent:GetFrameLevel() + 5)
  button:ClearAllPoints()
  button:SetPoint("LEFT", leftRegion, "LEFT", 0, 0)
  button:SetPoint("BOTTOM", bottomRegion, "BOTTOM", 0, 0)
  button:SetScript("OnClick", OnClick)
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
      ShowProgressOnButton(self, lastText, lastColor)
    end
  end)
  button:SetScript("OnHide", HideProgressTooltip)
  return button
end

local function EnsureShoppingButton()
  if AP.fullScanShoppingButton then return true end
  local shoppingFrame = _G.AuctionatorShoppingFrame
  local inset = shoppingFrame and shoppingFrame.ShoppingResultsInset
  local bg = inset and inset.Bg
  local exportButton = shoppingFrame and shoppingFrame.ExportCSV
  if not shoppingFrame or not bg or not exportButton then return false end
  AP.fullScanShoppingButton = CreateButton(
    "AuctionatorPlusFullScanShoppingButton", shoppingFrame, bg, exportButton)
  return true
end

local function EnsureSellingButton()
  if AP.fullScanSellingButton then return true end
  local sellingFrame = _G.AuctionatorSellingFrame
  local buyFrame = sellingFrame and sellingFrame.BuyFrame
  local currentPrices = buyFrame and buyFrame.CurrentPrices
  local inset = currentPrices and currentPrices.Inset
  local bg = inset and inset.Bg
  local refresh = currentPrices and currentPrices.RefreshButton
  local history = buyFrame and buyFrame.HistoryButton
  if not buyFrame or not bg or not refresh or not history then return false end
  RepositionSellingBottomRow(buyFrame)
  local btn = CreateButton(
    "AuctionatorPlusFullScanSellingButton", buyFrame, bg, refresh)
  btn:SetPoint("RIGHT", history, "LEFT", -BUTTON_GAP, 0)
  AP.fullScanSellingButton = btn
  return true
end

function AP.FullScanButton.Ensure()
  local shoppingReady = EnsureShoppingButton()
  local sellingReady = EnsureSellingButton()
  return shoppingReady and sellingReady
end
