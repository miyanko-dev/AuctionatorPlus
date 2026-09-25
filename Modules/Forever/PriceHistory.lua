local _, AP = ...

-- Forever half of the tooltip rows: item tooltips route through the tooltip data processor on this client

local function shown(frame)
    return frame ~= nil and frame:IsVisible()
end

-- Seller's colours in the selling views, buyer's colours anywhere else in an open Auction House
function AP.Tooltip.TrendMode()
    local ah = AuctionHouseFrame
    if not shown(ah) then return AP.Trend.UP_GREEN end
    if shown(AuctionatorSellingFrame) or shown(ah.ItemSellFrame) or shown(ah.CommoditiesSellFrame) then
        return AP.Trend.UP_GREEN
    end
    return AP.Trend.UP_RED
end

-- Only the two player-facing tooltips get rows
local PLAYER_TOOLTIPS = { [GameTooltip] = true, [ItemRefTooltip] = true }

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
    if not PLAYER_TOOLTIPS[tooltip] then return end
    local _, itemLink = TooltipUtil.GetDisplayedItem(tooltip)
    if itemLink then pcall(AP.Tooltip.AddPriceRows, tooltip, itemLink) end
end)
