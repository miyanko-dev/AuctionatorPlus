local _, AP = ...

-- Era half of the stat parser: this client has no C_TooltipInfo, so item text comes off a hidden scan tooltip

-- Vanilla gear carries no combat ratings, and its piercing lines use a wording the parser does not map, so the stat filter leaves haste, expertise and both piercings out
AP.ItemStats.RATED_GEAR = false

-- The TextLeft/TextRight regions are only reachable through the tooltip's global name
local SCAN_TIP_NAME = "AuctionatorPlusScanTooltip"
local scanTip

local function scanTooltip()
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", SCAN_TIP_NAME, nil, "GameTooltipTemplate")
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return scanTip
end

local function lineText(side, index)
    local region = _G[SCAN_TIP_NAME .. side .. index]
    local text = region and region:GetText()
    if type(text) == "string" and text ~= "" then return text end
    return nil
end

-- Lowercased tooltip text for an item link or item string, left then right text per line; nil while the item is uncached
function AP.ItemStats.Text(itemRef)
    if type(itemRef) ~= "string" or itemRef == "" then return nil end
    local tip = scanTooltip()

    -- Re-own every scan: SetHyperlink can no-op on a tooltip already showing the same link
    tip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tip:ClearLines()
    if not pcall(tip.SetHyperlink, tip, itemRef) then return nil end

    local parts = {}
    for index = 1, tip:NumLines() or 0 do
        parts[#parts + 1] = lineText("TextLeft", index)
        parts[#parts + 1] = lineText("TextRight", index)
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "\n"):lower()
end
