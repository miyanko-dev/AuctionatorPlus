local _, AP = ...

-- Wrap the Auctionator internals this addon consumes; pcall where Auctionator can raise on bad input.
AP.Bridge = {}

local callerID = AP.Constants.CallerID

-- Auctionator price-database key for an item link; nil when the link is unusable.
function AP.Bridge.DBKeyForLink(itemLink)
    if not itemLink then return nil end
    local ok, key = pcall(Auctionator.Utilities.BasicDBKeyFromLink, itemLink)
    if not ok then return nil end
    return key
end

-- Price-database keys, most specific first (gear suffix key, then base item id); the callback is immediate on the legacy AH client, the basic key covers a deferred one.
function AP.Bridge.DBKeysForLink(itemLink)
    if not itemLink then return nil end

    local keys = nil
    pcall(Auctionator.Utilities.DBKeyFromLink, itemLink, function(result)
        keys = result
    end)
    if type(keys) == "table" and #keys > 0 then return keys end

    local basicKey = AP.Bridge.DBKeyForLink(itemLink)
    if basicKey then return { basicKey } end
    return nil
end

-- Historical auction price from Auctionator's database; nil when unknown.
function AP.Bridge.AuctionPrice(itemLink)
    if not itemLink then return nil end
    local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, callerID, itemLink)
    if ok and type(price) == "number" and price > 0 then return price end
    return nil
end

-- Subscribe to Auctionator event-bus events; returns the listener for later register/unregister calls.
function AP.Bridge.Listen(events, handler)
    local listener = { ReceiveEvent = handler }
    Auctionator.EventBus:Register(listener, events)
    return listener
end
