local _, AP = ...

local BUTTON_GAP = 2

local function CreateFlipButton()
  if AP.toggleButton then return true end

  local shoppingFrame = _G.AuctionatorShoppingFrame
  local fullScanButton = AP.fullScanShoppingButton
  if not shoppingFrame or not fullScanButton then return false end

  local button = CreateFrame(
    "Button", "AuctionatorPlusArbitrageButton", shoppingFrame, "UIPanelButtonTemplate")
  button:SetSize(150, 22)
  button:SetText("Arbitrage")
  button:SetPoint("LEFT", fullScanButton, "RIGHT", BUTTON_GAP, 0)
  button:SetFrameStrata(shoppingFrame:GetFrameStrata())
  button:SetFrameLevel(shoppingFrame:GetFrameLevel() + 5)
  button:SetScript("OnClick", AP.Panel.Toggle)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Toggle Arbitrage panel")
    GameTooltip:AddLine(
      "Surfaces items whose lowest auctions span a price gap above the configured margin.",
      1, 1, 1, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", GameTooltip_Hide)
  button:Show()

  AP.toggleButton = button
  return true
end

local function SetFinderButtonsShown(shown)
  if AP.toggleButton then
    if shown then AP.toggleButton:Show() else AP.toggleButton:Hide() end
  end
  if AP.fullScanShoppingButton then
    if shown then AP.fullScanShoppingButton:Show() else AP.fullScanShoppingButton:Hide() end
  end
end

local function SyncFinderButtonVisibility()
  local buyFrame = _G.AuctionatorBuyFrame
  SetFinderButtonsShown(not (buyFrame and buyFrame:IsShown()))
end

local function HookBuyFrameVisibility()
  if AP.buyFrameHooked then return true end
  if not AP.toggleButton then return false end

  local buyFrame = _G.AuctionatorBuyFrame
  if not buyFrame then return false end

  buyFrame:HookScript("OnShow", function() SetFinderButtonsShown(false) end)
  buyFrame:HookScript("OnHide", function() SetFinderButtonsShown(true) end)

  local shoppingFrame = _G.AuctionatorShoppingFrame
  if shoppingFrame then
    shoppingFrame:HookScript("OnShow", SyncFinderButtonVisibility)
  end

  SyncFinderButtonVisibility()

  AP.buyFrameHooked = true
  return true
end

-- The Auctionator frames these attach to are created on (or shortly after) the
-- first auction-house open, so retry until every piece is in place.
local function EnsureToggleButton(attempt)
  attempt = attempt or 1
  local fullScanReady = AP.FullScanButton.Ensure()
  local flipReady = fullScanReady and CreateFlipButton()
  local buyHooked = flipReady and HookBuyFrameVisibility()
  local watchReady = AP.SellingWatch.Ensure()
  if (fullScanReady and flipReady and buyHooked and watchReady) or attempt > 20 then return end
  C_Timer.After(0.5, function() EnsureToggleButton(attempt + 1) end)
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:RegisterEvent("AUCTION_HOUSE_SHOW")
bootstrap:RegisterEvent("AUCTION_HOUSE_CLOSED")
bootstrap:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    AP.LoadSettings()
    AP.SellingWatch.Ensure()

  elseif event == "AUCTION_HOUSE_SHOW" then
    AP.ahOpen = true
    EnsureToggleButton()

  elseif event == "AUCTION_HOUSE_CLOSED" then
    AP.ahOpen = false
    AP.Arbitrage.Abort()
    if AP.panel then AP.panel:Hide() end
  end
end)
