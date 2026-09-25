local _, AP = ...

-- Era half of the tooltip rows: the tooltip data processor does not load on vanilla, so the item-setting methods are post-hooked

-- Buyer's colours in Auctionator's shopping tab and Blizzard's browse tab, seller's colours anywhere else; IsVisible so a deselected tab does not count
function AP.Tooltip.TrendMode()
    if AuctionatorShoppingFrame and AuctionatorShoppingFrame:IsVisible() then
        return AP.Trend.UP_RED
    end
    if AuctionFrameBrowse and AuctionFrameBrowse:IsVisible() then
        return AP.Trend.UP_RED
    end
    return AP.Trend.UP_GREEN
end

-- Hook only the item-setting methods that exist on this client; the list spans several flavors
local TOOLTIP_METHODS = {
    "SetBagItem", "SetBuybackItem", "SetMerchantItem", "SetInventoryItem",
    "SetGuildBankItem", "SetLootItem", "SetLootRollItem",
    "SetQuestItem", "SetQuestLogItem", "SetSendMailItem", "SetInboxItem",
    "SetTradePlayerItem", "SetTradeTargetItem", "SetAuctionItem",
    "SetItemByID", "SetHyperlink", "SetTradeSkillItem", "SetCraftItem",
    "SetItemByGUID", "SetRecipeReagentItem", "SetRecipeResultItem",
    "SetItemKey",
}

local function dispatch(tooltip)
    if not tooltip or not tooltip.GetItem then return end
    local _, itemLink = tooltip:GetItem()
    if not itemLink or itemLink == "" then return end
    pcall(AP.Tooltip.AddPriceRows, tooltip, itemLink)
end

for _, methodName in ipairs(TOOLTIP_METHODS) do
    if GameTooltip[methodName] then
        hooksecurefunc(GameTooltip, methodName, dispatch)
    end
end
hooksecurefunc(ItemRefTooltip, "SetHyperlink", dispatch)
