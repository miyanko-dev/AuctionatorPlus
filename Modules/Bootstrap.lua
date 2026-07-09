local _, AP = ...

-- The full-scan shopping button sits over the results inset, which the buy
-- screen covers; keep the button hidden while that screen is up.
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

-- The Auctionator frames these attach to are created on (or shortly after) the
-- first auction-house open, so retry until every piece is in place.
local function EnsureButtons(attempt)
  attempt = attempt or 1
  local fullScanReady = AP.FullScanButton.Ensure()
  local buyHooked = fullScanReady and HookBuyFrameVisibility()
  local watchReady = AP.SellingWatch.Ensure()
  if (fullScanReady and buyHooked and watchReady) or attempt > 20 then return end
  C_Timer.After(0.5, function() EnsureButtons(attempt + 1) end)
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
    EnsureButtons()

  elseif event == "AUCTION_HOUSE_CLOSED" then
    AP.ahOpen = false
  end
end)
