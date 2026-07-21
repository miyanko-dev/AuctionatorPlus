local _, AP = ...

AP.BagGlow = {}

local STRONG_PCT = 15  -- both values at or above this: green

-- Green uses the premade atlas, far brighter under ADD blending, so it stays visible next to green-quality borders; yellow has no premade atlas and keeps the softer tinted white one.
local TIER_GLOW = {
  green  = { atlas = "bags-glow-green", tint = { 1, 1, 1 } },
  yellow = { atlas = "bags-glow-white", tint = { 1, 0.9, 0.1 } },
}

-- Glow over a bag item's icon in the selling tab based on how its last known price sits against the 21-day Auctionator average and the TSM market value. Green when both relative values reach +15%; yellow when only one reaches it or both are positive below it, so the user can double check those items manually.
local function Classify(itemLink)
  local price = AP.Bridge.AuctionPrice(itemLink)
  local localPct = AP.Trend.Percent(price, AP.Trend.AverageFor(itemLink))
  local tsmPct = AP.Trend.Percent(price, AP.TSMFeed and AP.TSMFeed.MarketValueForLink(itemLink))

  local localStrong = localPct ~= nil and localPct >= STRONG_PCT
  local tsmStrong = tsmPct ~= nil and tsmPct >= STRONG_PCT
  local bothPositive = localPct ~= nil and localPct > 0
                   and tsmPct ~= nil and tsmPct > 0

  if localStrong and tsmStrong then
    return "green"
  end
  if localStrong or tsmStrong or bothPositive then
    return "yellow"
  end
  return nil
end

local function EnsureGlow(button)
  local glow = button.auctionatorPlusGlow
  if not glow then
    glow = button:CreateTexture(nil, "OVERLAY", nil, 1)
    glow:SetAllPoints(button.Icon)
    glow:SetBlendMode("ADD")
    button.auctionatorPlusGlow = glow
  end
  return glow
end

local function Apply(button, itemLink)
  local tier = itemLink and Classify(itemLink)
  if tier then
    local style = TIER_GLOW[tier]
    local glow = EnsureGlow(button)
    glow:SetAtlas(style.atlas)
    glow:SetVertexColor(style.tint[1], style.tint[2], style.tint[3])
    glow:Show()
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
