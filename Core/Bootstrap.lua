local function CreateToggleButton()
  if FF.toggleButton then return true end
  if not FF.Adapter or not FF.Adapter.GetAnchorButton then return false end

  local anchor = FF.Adapter.GetAnchorButton()
  if not anchor then return false end

  local button = CreateFrame(
    "Button", "FlipperScanButton",
    AuctionatorShoppingFrame, "UIPanelButtonTemplate"
  )
  button:SetSize(150, 22)
  button:SetText("Flip Finder")
  button:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
  button:SetFrameStrata(anchor:GetFrameStrata())
  button:SetFrameLevel(anchor:GetFrameLevel() + 1)
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

local function CreateStatToggleButton()
  if FF.statToggleButton then return true end
  if not FF.toggleButton then return false end

  local button = CreateFrame(
    "Button", "FlipperStatFilterButton",
    AuctionatorShoppingFrame, "UIPanelButtonTemplate"
  )
  button:SetSize(120, 22)
  button:SetText("Stat Filter")
  button:SetPoint("RIGHT", FF.toggleButton, "LEFT", -4, 0)
  button:SetFrameStrata(FF.toggleButton:GetFrameStrata())
  button:SetFrameLevel(FF.toggleButton:GetFrameLevel())
  button:SetScript("OnClick", FF.StatPanel.Toggle)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Toggle Stat Filter panel")
    GameTooltip:AddLine(
      "Filters Auctionator shopping results by item stats. Enter comma-separated terms like agility, stamina, dps.",
      1, 1, 1, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", GameTooltip_Hide)
  button:Show()

  FF.statToggleButton = button
  return true
end

local function EnsureToggleButton(attempt)
  attempt = attempt or 1
  local flipReady = CreateToggleButton()
  local statReady = flipReady and CreateStatToggleButton()
  if (flipReady and statReady) or attempt > 20 then return end
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
