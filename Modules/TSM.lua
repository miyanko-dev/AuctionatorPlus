local _, AP = ...

-- TSM market data through TSM's public API, so the payload format, realm and region keying and the AppHelper import stay TSM's problem
-- DBMarket is the realm market value in copper, as the installed TSM v4.14.77 defines it. That build has no 16001 toc, so TSM_API stays nil and every TSM row stays hidden until TSM ships for WoW Forever
AP.TSM = {}

local MARKET_SOURCE = "DBMarket"

-- TSM item string for a link, an item string or an auction item key; keys pool suffixed gear into the base item, and TSM itself falls back to the base item when a variant has no data
local function itemStringFor(itemRef)
    if not TSM_API then return nil end
    if type(itemRef) == "table" and itemRef.itemID then
        return "i:" .. itemRef.itemID
    end
    if type(itemRef) == "string" and itemRef ~= "" then
        local ok, itemString = pcall(TSM_API.ToItemString, itemRef)
        return ok and itemString or nil
    end
    return nil
end

-- Realm market value in copper; nil when TSM is absent, has no figure or rejects the input
function AP.TSM.MarketValueFor(itemRef)
    local itemString = itemStringFor(itemRef)
    if not itemString then return nil end
    local ok, amount = pcall(TSM_API.GetCustomPriceValue, MARKET_SOURCE, itemString)
    if ok and type(amount) == "number" and amount > 0 then return amount end
    return nil
end
