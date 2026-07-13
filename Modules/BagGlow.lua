local _, AP = ...

AP.BagGlow = {}

local FAVORABLE_PCT = 0  -- both relative values must exceed this
local GLOW_ATLAS = "bags-glow-green"

-- Fade a green glow over a bag item's icon in the selling tab while its last known price sits above both the 21-day Auctionator average and the TSM market value; a glow stays readable on green-quality items whose border is already green.
local function IsFavorable(itemLink)
  local price = AP.Bridge.AuctionPrice(itemLink)
  local localPct = AP.Trend.Percent(price, AP.Trend.AverageFor(itemLink))
  local tsmPct = AP.Trend.Percent(price, AP.TSMFeed and AP.TSMFeed.MarketValueForLink(itemLink))
  return localPct ~= nil and localPct > FAVORABLE_PCT
     and tsmPct ~= nil and tsmPct > FAVORABLE_PCT
end

local function EnsureGlow(button)
  local glow = button.auctionatorPlusGlow
  if not glow then
    glow = button:CreateTexture(nil, "OVERLAY", nil, 1)
    glow:SetAllPoints(button.Icon)
    glow:SetAtlas(GLOW_ATLAS)
    glow:SetBlendMode("ADD")
    button.auctionatorPlusGlow = glow
  end
  return glow
end

local function Apply(button, itemLink)
  if itemLink and IsFavorable(itemLink) then
    EnsureGlow(button):Show()
  elseif button.auctionatorPlusGlow then
    button.auctionatorPlusGlow:Hide()
  end
end

-- Re-evaluate every bag button in place, for callers that changed prices without touching the bags (e.g. the auto scan).
function AP.BagGlow.Repaint()
  local listing = _G.AuctionatorSellingFrame and _G.AuctionatorSellingFrame.BagListing
  local view = listing and listing.View
  if not view or type(view.itemMap) ~= "table" then return end

  for _, group in pairs(view.itemMap) do
    for _, button in pairs(group) do
      if type(button) == "table" and button.itemInfo then
        Apply(button, button.itemInfo.itemLink)
      end
    end
  end
end

-- Post-hook the mixin before any buttons exist; SetItemInfo runs on every refresh, so recycled buttons drop the glow on their own when an item stops being favorable.
hooksecurefunc(AuctionatorGroupsViewItemMixin, "SetItemInfo", function(self, info)
  Apply(self, info and info.itemLink)
end)
