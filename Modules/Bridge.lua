local _, AP = ...

-- Calls into Auctionator's functions, pcalled wherever Auctionator can raise on bad input; frames, mixins and event names are read in place by the modules. Item references are either an item link or an auction item key table
AP.Bridge = {}

function AP.Bridge.IsEquipment(classID)
    return Auctionator.Utilities.IsEquipment(classID)
end

function AP.Bridge.Money(amount)
    return Auctionator.Utilities.CreatePaddedMoneyString(amount)
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

-- ===== Price database =====
-- Auctionator answers through a callback that runs at once for cached items; an uncached link yields nil instead of waiting
local function keysForLink(itemLink)
    local keys
    pcall(Auctionator.Utilities.DBKeyFromLink, itemLink, function(result) keys = result end)
    if type(keys) == "table" and #keys > 0 then return keys end
    return nil
end

local function keysForItemKey(itemKey)
    local ok, keys = pcall(Auctionator.Utilities.DBKeyFromBrowseResult, { itemKey = itemKey })
    if ok and type(keys) == "table" and #keys > 0 then return keys end
    return nil
end

-- Price-database keys, most specific first; nil when the reference is unusable
function AP.Bridge.DBKeys(itemRef)
    if type(itemRef) == "table" and itemRef.itemID ~= nil then return keysForItemKey(itemRef) end
    if type(itemRef) == "string" then return keysForLink(itemRef) end
    return nil
end

-- Last recorded minimum price; nil when unknown or before Auctionator opened its database
function AP.Bridge.AuctionPrice(itemRef)
    local db = Auctionator.Database
    local keys = db and AP.Bridge.DBKeys(itemRef)
    if not keys then return nil end
    local ok, price = pcall(db.GetFirstPrice, db, keys)
    if ok and type(price) == "number" and price > 0 then return price end
    return nil
end

-- Days since Auctionator last recorded a price; nil without history
function AP.Bridge.PriceAge(itemRef)
    local db = Auctionator.Database
    for _, dbKey in ipairs(db and AP.Bridge.DBKeys(itemRef) or {}) do
        local ok, days = pcall(db.GetPriceAge, db, dbKey)
        if ok and type(days) == "number" then return days end
    end
    return nil
end

-- Daily rows for one database key, newest first; empty without history
function AP.Bridge.PriceHistory(dbKey)
    local db = Auctionator.Database
    if not db then return {} end
    local ok, history = pcall(db.GetPriceHistory, db, dbKey)
    return ok and type(history) == "table" and history or {}
end

-- Record a live minimum price under every key of the item, the way Auctionator's own sell search does
function AP.Bridge.RecordPrice(itemKey, price)
    local db = Auctionator.Database
    if not db or type(price) ~= "number" or price <= 0 then return end
    for _, dbKey in ipairs(keysForItemKey(itemKey) or {}) do
        pcall(db.SetPrice, db, dbKey, price)
    end
end

-- ===== Event bus =====
-- Subscribe a handler for the whole session; listeners are tables with a ReceiveEvent method, called as (listener, eventName, ...)
function AP.Bridge.Listen(events, handler)
    local listener = { ReceiveEvent = handler }
    Auctionator.EventBus:Register(listener, events)
    return listener
end

-- Fire an event-bus event from this addon, registering a source the way Auctionator requires
local source = {}
local function fire(eventName, ...)
    Auctionator.EventBus
        :RegisterSource(source, "AuctionatorPlus")
        :Fire(source, eventName, ...)
        :UnregisterSource(source)
end

-- Set the sale price to an exact amount, skipping Auctionator's undercut
function AP.Bridge.SelectPrice(price)
    fire(Auctionator.Selling.Events.PriceSelected, { buyout = price }, false)
end

-- Re-run the slotted item's own current-prices search
function AP.Bridge.RefreshSellSearch()
    fire(Auctionator.Selling.Events.RefreshSearch)
end

-- ===== Auction house =====
-- Auctionator's replicate full scan, which it rate-limits itself
function AP.Bridge.StartFullScan()
    local scanFrame = Auctionator.State.FullScanFrameRef
    if scanFrame then scanFrame:InitiateScan() end
end

-- Category browse through Auctionator's throttle queue
function AP.Bridge.Browse(query)
    pcall(Auctionator.AH.SendBrowseQuery, query)
end

-- False until the queued browse was actually sent, so an earlier browse's results never pass for it
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
