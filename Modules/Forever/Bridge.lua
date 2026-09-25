local _, AP = ...

-- Forever half of the bridge: Auctionator's ModernAH build, where items are links or auction item keys and searches queue behind Auctionator's throttle

-- Item references are either an item link or an auction item key table
local function isItemKey(itemRef)
    return type(itemRef) == "table" and itemRef.itemID ~= nil
end

-- Bare item key for a gear search, the same key Auctionator's own sell search uses
function AP.Bridge.BaseItemKey(itemID)
    return { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
end

function AP.Bridge.ItemKeyString(itemKey)
    return Auctionator.Utilities.ItemKeyString(itemKey)
end

function AP.Bridge.SameItemKey(a, b)
    return AP.Bridge.ItemKeyString(a) == AP.Bridge.ItemKeyString(b)
end

local function keysForItemKey(itemKey)
    local ok, keys = pcall(Auctionator.Utilities.DBKeyFromBrowseResult, { itemKey = itemKey })
    if ok and type(keys) == "table" and #keys > 0 then return keys end
    return nil
end

-- Price-database keys, most specific first; nil when the reference is unusable
function AP.Bridge.DBKeys(itemRef)
    if isItemKey(itemRef) then return keysForItemKey(itemRef) end
    if type(itemRef) == "string" then return AP.Bridge.KeysForLink(itemRef) end
    return nil
end

-- Record a live minimum price under every key of the item, the way Auctionator's own sell search does
function AP.Bridge.RecordPrice(itemKey, price)
    local db = Auctionator.Database
    if not db or type(price) ~= "number" or price <= 0 then return end
    for _, dbKey in ipairs(keysForItemKey(itemKey) or {}) do
        pcall(db.SetPrice, db, dbKey, price)
    end
end

-- Set the sale price to an exact amount, skipping Auctionator's undercut
function AP.Bridge.SelectPrice(price)
    AP.Bridge.Fire(Auctionator.Selling.Events.PriceSelected, { buyout = price }, false)
end

-- Re-run the slotted item's own current-prices search
function AP.Bridge.RefreshSellSearch()
    AP.Bridge.Fire(Auctionator.Selling.Events.RefreshSearch)
end

-- Category browse through Auctionator's throttle queue
function AP.Bridge.Browse(query)
    pcall(Auctionator.AH.SendBrowseQuery, query)
end

function AP.Bridge.BrowseFinished()
    return Auctionator.AH.HasFullBrowseResults()
end

function AP.Bridge.BrowseMore()
    pcall(Auctionator.AH.RequestMoreBrowseResults)
end

-- Single-item search through Auctionator's retrying scanner; gear uses the sell search so every suffix variant answers
function AP.Bridge.SearchItem(itemKey, isGear)
    if isGear then
        return pcall(Auctionator.AH.SendSellSearchQueryByItemKey, itemKey, { Auctionator.Constants.ItemResultsSorts }, false)
    end
    return pcall(Auctionator.AH.SendSearchQueryByItemKey, itemKey, { Auctionator.Constants.CommodityResultsSorts }, false)
end

-- Item key of a shopping result; nil for missing-term placeholders
function AP.Bridge.ShoppingItemRef(entry)
    return entry.itemKey
end
