local BUTTON_GAP = 4

local function GetShoppingAnchor()
  local shoppingFrame = _G.AuctionatorShoppingFrame
  if not shoppingFrame then return nil, nil end
  return shoppingFrame, shoppingFrame.ExportCSV
end

local function CreateToggleButton()
  if FF.toggleButton then return true end

  local shoppingFrame, exportButton = GetShoppingAnchor()
  if not shoppingFrame or not exportButton then return false end

  local button = CreateFrame("Button", "FlipperScanButton", shoppingFrame, "UIPanelButtonTemplate")
  button:SetSize(150, 22)
  button:SetText("Flip Finder")
  button:SetPoint("RIGHT", exportButton, "LEFT", -BUTTON_GAP, 0)
  button:SetFrameStrata(shoppingFrame:GetFrameStrata())
  button:SetFrameLevel(shoppingFrame:GetFrameLevel() + 5)
  button:SetScript("OnClick", FF.Panel.Toggle)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Toggle Flip Finder panel")
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

local function CreateStatButton()
  if FF.statToggleButton then return true end
  if not FF.toggleButton then return false end

  local button = CreateFrame("Button", "FlipperStatButton", FF.toggleButton:GetParent(), "UIPanelButtonTemplate")
  button:SetSize(120, 22)
  button:SetText("Stat Finder")
  button:SetPoint("BOTTOMRIGHT", FF.toggleButton, "BOTTOMLEFT", -BUTTON_GAP, 0)
  button:SetFrameStrata(FF.toggleButton:GetFrameStrata())
  button:SetFrameLevel(FF.toggleButton:GetFrameLevel())
  button:SetScript("OnClick", FF.StatPanel.Toggle)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Toggle Stat Finder panel")
    GameTooltip:AddLine(
      "Finds items in Auctionator shopping results by item stats. Enter comma-separated terms like agility, stamina, dps.",
      1, 1, 1, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", GameTooltip_Hide)
  button:Show()

  FF.statToggleButton = button
  return true
end

local function SetFinderButtonsShown(shown)
  if FF.toggleButton then
    if shown then FF.toggleButton:Show() else FF.toggleButton:Hide() end
  end
  if FF.statToggleButton then
    if shown then FF.statToggleButton:Show() else FF.statToggleButton:Hide() end
  end
end

local function SyncFinderButtonVisibility()
  local buyFrame = _G.AuctionatorBuyFrame
  SetFinderButtonsShown(not (buyFrame and buyFrame:IsShown()))
end

local function HookBuyFrameVisibility()
  if FF.buyFrameHooked then return true end
  if not (FF.toggleButton and FF.statToggleButton) then return false end

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
  local flipReady = CreateToggleButton()
  local statReady = flipReady and CreateStatButton()
  local buyHooked = statReady and HookBuyFrameVisibility()
  local fullScanReady = FF.FullScanButton and FF.FullScanButton.Ensure()
  if (flipReady and statReady and buyHooked and fullScanReady) or attempt > 20 then return end
  C_Timer.After(0.5, function() EnsureToggleButton(attempt + 1) end)
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:RegisterEvent("AUCTION_HOUSE_SHOW")
bootstrap:RegisterEvent("AUCTION_HOUSE_CLOSED")
bootstrap:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    if FF.Adapter and FF.Adapter.RegisterEventBus then
      FF.Adapter.RegisterEventBus()
    end
    if FF.Adapter and FF.Adapter.RegisterTooltipHook and FF.Tooltip and FF.Tooltip.Apply then
      FF.Adapter.RegisterTooltipHook(FF.Tooltip.Apply)
    end

  elseif event == "AUCTION_HOUSE_SHOW" then
    if FF.Adapter and FF.Adapter.RegisterEventBus then
      FF.Adapter.RegisterEventBus()
    end
    EnsureToggleButton()

  elseif event == "AUCTION_HOUSE_CLOSED" then
    FF.Scanner.Abort()
    if FF.StatFilter and FF.StatFilter.Abort then FF.StatFilter.Abort() end
    if FF.panel then FF.panel:Hide() end
    if FF.statPanel then FF.statPanel:Hide() end
  end
end)
