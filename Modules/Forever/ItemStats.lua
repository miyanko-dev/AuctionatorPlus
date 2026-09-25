local _, AP = ...

-- Forever half of the stat parser: item text comes from the client's tooltip data

-- Forever gear carries combat ratings (Camelot/PaperDollFrameConstants.lua lists haste, expertise and both piercings), so the stat filter offers them
AP.ItemStats.RATED_GEAR = true

-- Flatten tooltip data into lowercased text, left then right text per line; nil while the item is uncached
local function textOf(data)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local parts = {}
    for _, line in ipairs(data.lines) do
        if type(line.leftText) == "string" and line.leftText ~= "" then parts[#parts + 1] = line.leftText end
        if type(line.rightText) == "string" and line.rightText ~= "" then parts[#parts + 1] = line.rightText end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "\n"):lower()
end

-- Tooltip text for an item link or an auction item key. Vanilla random suffixes carry fixed stats per suffix id, so a key renders the exact stats without a full link
function AP.ItemStats.Text(itemRef)
    local ok, data
    if type(itemRef) == "table" and itemRef.itemID then
        ok, data = pcall(C_TooltipInfo.GetItemKey, itemRef.itemID, itemRef.itemLevel or 0, itemRef.itemSuffix or 0)
    elseif type(itemRef) == "string" and itemRef ~= "" then
        ok, data = pcall(C_TooltipInfo.GetHyperlink, itemRef)
    end
    return ok and textOf(data) or nil
end
