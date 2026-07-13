local _, AP = ...

-- Hide the full-scan shopping button while the buy screen covers the results inset it sits over.
local function SetFullScanButtonShown(shown)
  if AP.fullScanShoppingButton then
    if shown then AP.fullScanShoppingButton:Show() else AP.fullScanShoppingButton:Hide() end
  end
end

local function SyncFullScanButtonVisibility()
  local buyFrame = _G.AuctionatorBuyFrame
  SetFullScanButtonShown(not (buyFrame and buyFrame:IsShown()))
end

local function HookBuyFrameVisibility()
  if AP.buyFrameHooked then return true end
  if not AP.fullScanShoppingButton then return false end

  local buyFrame = _G.AuctionatorBuyFrame
  if not buyFrame then return false end

  buyFrame:HookScript("OnShow", function() SetFullScanButtonShown(false) end)
  buyFrame:HookScript("OnHide", function() SetFullScanButtonShown(true) end)

  local shoppingFrame = _G.AuctionatorShoppingFrame
  if shoppingFrame then
    shoppingFrame:HookScript("OnShow", SyncFullScanButtonVisibility)
  end

  SyncFullScanButtonVisibility()

  AP.buyFrameHooked = true
  return true
end

-- Retry until every piece is in place; Auctionator creates the host frames on or shortly after first AH open.
local function EnsureButtons(attempt)
  attempt = attempt or 1
  local fullScanReady = AP.FullScanButton.Ensure()
  local buyHooked = fullScanReady and HookBuyFrameVisibility()
  local watchReady = AP.SellingWatch.Ensure()
  local saleScanReady = AP.SaleScan.Ensure()
  if (fullScanReady and buyHooked and watchReady and saleScanReady) or attempt > 20 then return end
  C_Timer.After(0.5, function() EnsureButtons(attempt + 1) end)
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:RegisterEvent("AUCTION_HOUSE_SHOW")
bootstrap:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    AP.LoadSettings()
    AP.SellingWatch.Ensure()

  elseif event == "AUCTION_HOUSE_SHOW" then
    EnsureButtons()
  end
end)
