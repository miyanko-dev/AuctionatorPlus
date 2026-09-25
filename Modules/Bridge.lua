local _, AP = ...

-- Calls into Auctionator functions that its Era and Forever builds define alike, pcalled wherever Auctionator can raise on bad input. Each client's half adds DBKeys and its auction-house calls; frames, mixins and event names are read in place by the modules
AP.Bridge = {}

function AP.Bridge.IsEquipment(classID)
    return Auctionator.Utilities.IsEquipment(classID)
end

function AP.Bridge.Money(amount)
    return Auctionator.Utilities.CreatePaddedMoneyString(amount)
end

-- Auctionator answers through a callback that runs at once on Era and for cached items on Forever; an uncached Forever link yields nil instead of waiting
function AP.Bridge.KeysForLink(itemLink)
    local keys
    pcall(Auctionator.Utilities.DBKeyFromLink, itemLink, function(result) keys = result end)
    if type(keys) == "table" and #keys > 0 then return keys end
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

-- Event-bus listeners are tables with a ReceiveEvent method, called as (listener, eventName, ...)
function AP.Bridge.Register(listener, events)
    Auctionator.EventBus:Register(listener, events)
end

function AP.Bridge.Unregister(listener, events)
    Auctionator.EventBus:Unregister(listener, events)
end

-- Subscribe a handler for the whole session; the listener comes back for later Register and Unregister calls
function AP.Bridge.Listen(events, handler)
    local listener = { ReceiveEvent = handler }
    AP.Bridge.Register(listener, events)
    return listener
end

-- Fire an event-bus event from this addon, registering a source the way Auctionator requires
local source = {}
function AP.Bridge.Fire(eventName, ...)
    Auctionator.EventBus
        :RegisterSource(source, "AuctionatorPlus")
        :Fire(source, eventName, ...)
        :UnregisterSource(source)
end

-- Auctionator's full scan, which it rate-limits itself
function AP.Bridge.StartFullScan()
    local scanFrame = Auctionator.State.FullScanFrameRef
    if scanFrame then scanFrame:InitiateScan() end
end
