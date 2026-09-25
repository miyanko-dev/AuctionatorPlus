local _, AP = ...

-- TSM market data through TSM's public API, so the payload format, realm and region keying and the AppHelper import stay TSM's problem
-- Semantics as the installed TSM v4.14.77 defines them: DBMarket is the realm market value in copper, DBRegionSaleRate the region sale share as a 0-1 fraction. That build loads on Classic Era; its toc lacks 16001, so on WoW Forever TSM_API stays nil and every TSM row stays hidden
AP.TSM = {}

local MARKET_SOURCE = "DBMarket"
local SALE_RATE_SOURCE = "DBRegionSaleRate"

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

-- Positive source value; nil when TSM is absent, has no figure or rejects the input
local function valueOf(source, itemRef)
    local itemString = itemStringFor(itemRef)
    if not itemString then return nil end
    local ok, amount = pcall(TSM_API.GetCustomPriceValue, source, itemString)
    if ok and type(amount) == "number" and amount > 0 then return amount end
    return nil
end

-- Realm market value in copper
function AP.TSM.MarketValueFor(itemRef)
    return valueOf(MARKET_SOURCE, itemRef)
end

-- Region-wide share of posted auctions that sell, in percent
function AP.TSM.SalePercentFor(itemRef)
    local rate = valueOf(SALE_RATE_SOURCE, itemRef)
    return rate and rate * 100
end

-- Sale rate as whole-percent text ("39%"); nil without a figure
function AP.TSM.SaleRateText(itemRef)
    local rate = AP.TSM.SalePercentFor(itemRef)
    return rate and ("%d%%"):format(math.floor(rate + 0.5))
end
