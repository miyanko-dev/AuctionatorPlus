local BUTTON_GAP = 2

local function CreateFlipButton()
  if FF.toggleButton then return true end

  local shoppingFrame = _G.AuctionatorShoppingFrame
  local fullScanButton = FF.fullScanShoppingButton
  if not shoppingFrame or not fullScanButton then return false end

  local button = CreateFrame("Button", "FlipperScanButton", shoppingFrame, "UIPanelButtonTemplate")
  button:SetSize(150, 22)
  button:SetText("Arbitrage")
  button:SetPoint("LEFT", fullScanButton, "RIGHT", BUTTON_GAP, 0)
  button:SetFrameStrata(shoppingFrame:GetFrameStrata())
  button:SetFrameLevel(shoppingFrame:GetFrameLevel() + 5)
  button:SetScript("OnClick", FF.Panel.Toggle)
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

  FF.toggleButton = button
  return true
end

local function SetFinderButtonsShown(shown)
  if FF.toggleButton then
    if shown then FF.toggleButton:Show() else FF.toggleButton:Hide() end
  end
  if FF.fullScanShoppingButton then
    if shown then FF.fullScanShoppingButton:Show() else FF.fullScanShoppingButton:Hide() end
  end
end

local function SyncFinderButtonVisibility()
  local buyFrame = _G.AuctionatorBuyFrame
  SetFinderButtonsShown(not (buyFrame and buyFrame:IsShown()))
end

local function HookBuyFrameVisibility()
  if FF.buyFrameHooked then return true end
  if not FF.toggleButton then return false end

  local buyFrame = _G.AuctionatorBuyFrame
  if not buyFrame then return false end

  buyFrame:HookScript("OnShow", function() SetFinderButtonsShown(false) end)
  buyFrame:HookScript("OnHide", function() SetFinderButtonsShown(true) end)

  local shoppingFrame = _G.AuctionatorShoppingFrame
  if shoppingFrame then
    shoppingFrame:HookScript("OnShow", SyncFinderButtonVisibility)
  end

  SyncFinderButtonVisibility()

  FF.buyFrameHooked = true
  return true
end

local function EnsureToggleButton(attempt)
  attempt = attempt or 1
  local fullScanReady = FF.FullScanButton and FF.FullScanButton.Ensure()
  local flipReady = fullScanReady and CreateFlipButton()
  local buyHooked = flipReady and HookBuyFrameVisibility()
  local watchReady = FF.SellingWatch and FF.SellingWatch.Ensure()
  if (fullScanReady and flipReady and buyHooked and watchReady) or attempt > 20 then return end
  C_Timer.After(0.5, function() EnsureToggleButton(attempt + 1) end)
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:RegisterEvent("AUCTION_HOUSE_SHOW")
bootstrap:RegisterEvent("AUCTION_HOUSE_CLOSED")
bootstrap:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    if FF.Settings and FF.Settings.Load then FF.Settings.Load() end
    if FF.Adapter and FF.Adapter.RegisterEventBus then
      FF.Adapter.RegisterEventBus()
    end
    if FF.SellingWatch and FF.SellingWatch.Ensure then
      FF.SellingWatch.Ensure()
    end
    if FF.ShoppingFilter and FF.ShoppingFilter.Hook then
      FF.ShoppingFilter.Hook()
    end
    if FF.Adapter and FF.Adapter.RegisterTooltipHook and FF.Tooltip and FF.Tooltip.Apply then
      FF.Adapter.RegisterTooltipHook(FF.Tooltip.Apply)
    end

  elseif event == "AUCTION_HOUSE_SHOW" then
    FF.ahOpen = true
    if FF.Adapter and FF.Adapter.RegisterEventBus then
      FF.Adapter.RegisterEventBus()
    end
    EnsureToggleButton()

  elseif event == "AUCTION_HOUSE_CLOSED" then
    FF.ahOpen = false
    FF.Scanner.Abort()
    if FF.panel then FF.panel:Hide() end
  end
end)
