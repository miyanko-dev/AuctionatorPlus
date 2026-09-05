local _, AP = ...

-- Wrap the Auctionator internals this addon consumes; pcall where Auctionator can raise on bad input
AP.Bridge = {}

-- Identifies this addon to Auctionator's public API
local callerID = "AuctionatorPlus"

-- Base-item price-database key; nil when the link is unusable
local function basicKey(itemLink)
    local ok, key = pcall(Auctionator.Utilities.BasicDBKeyFromLink, itemLink)
    return ok and key or nil
end

-- Price-database keys, most specific first (gear suffix key, then base item id); the callback is immediate on the legacy AH client, the basic key covers a deferred one
function AP.Bridge.DBKeys(itemLink)
    if not itemLink then return nil end

    local keys
    pcall(Auctionator.Utilities.DBKeyFromLink, itemLink, function(result) keys = result end)
    if type(keys) == "table" and #keys > 0 then return keys end

    local key = basicKey(itemLink)
    return key and { key } or nil
end

-- Historical auction price from Auctionator's database; nil when unknown
function AP.Bridge.AuctionPrice(itemLink)
    if not itemLink then return nil end
    local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, callerID, itemLink)
    if ok and type(price) == "number" and price > 0 then return price end
    return nil
end

-- Days since Auctionator last recorded a price for the link, most specific key first; nil without history
function AP.Bridge.PriceAge(itemLink)
    for _, dbKey in ipairs(AP.Bridge.DBKeys(itemLink) or {}) do
        local ok, days = pcall(Auctionator.Database.GetPriceAge, Auctionator.Database, dbKey)
        if ok and type(days) == "number" then return days end
    end
    return nil
end

-- Subscribe to Auctionator event-bus events; returns the listener for later register/unregister calls
function AP.Bridge.Listen(events, handler)
    local listener = { ReceiveEvent = handler }
    Auctionator.EventBus:Register(listener, events)
    return listener
end
