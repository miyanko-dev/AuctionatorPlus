local _, AP = ...

AP.BagGlow = {}

-- Premade atlas, bright under ADD blending, so it stays visible next to green-quality borders
local GLOW_ATLAS = "bags-glow-green"

-- Glow once the Relative Values reach the sell threshold: both of them when "Require both values" is on and TSM has data, otherwise any one; items whose TSM sale rate sits under the floor never glow
local function favorable(itemLink)
    local db = AP.DB()
    local rate = AP.TSMFeed.SalePercentFor(itemLink)
    if rate and rate < db.minSaleRate then return false end

    local price = AP.Bridge.AuctionPrice(itemLink)
    local localPct = AP.Trend.Percent(price, AP.Trend.AverageFor(itemLink))
    local tsmPct = AP.Trend.Percent(price, AP.TSMFeed.MarketValueFor(itemLink))
    local localHit = localPct ~= nil and localPct >= db.sellThresholdPct
    local tsmHit = tsmPct ~= nil and tsmPct >= db.sellThresholdPct
    if db.glowRequireBoth and tsmPct ~= nil then
        return localHit and tsmHit
    end
    return localHit or tsmHit
end

local function apply(button, itemLink)
    if itemLink and favorable(itemLink) then
        local glow = button.apGlow
        if not glow then
            glow = button:CreateTexture(nil, "OVERLAY", nil, 1)
            glow:SetAllPoints(button.Icon)
            glow:SetBlendMode("ADD")
            glow:SetAtlas(GLOW_ATLAS)
            button.apGlow = glow
        end
        glow:Show()
    elseif button.apGlow then
        button.apGlow:Hide()
    end
end

-- Re-evaluate every bag button in place, for callers that changed prices or settings without touching the bags
function AP.BagGlow.Repaint()
    local listing = _G.AuctionatorSellingFrame and _G.AuctionatorSellingFrame.BagListing
    local view = listing and listing.View
    if not view or type(view.itemMap) ~= "table" then return end

    for _, group in pairs(view.itemMap) do
        for _, button in pairs(group) do
            if type(button) == "table" and button.itemInfo then
                apply(button, button.itemInfo.itemLink)
            end
        end
    end
end

-- Post-hook the mixin before any buttons exist; SetItemInfo runs on every refresh, so recycled buttons drop the glow on their own when an item stops being favorable
hooksecurefunc(AuctionatorGroupsViewItemMixin, "SetItemInfo", function(self, info)
    apply(self, info and info.itemLink)
end)
