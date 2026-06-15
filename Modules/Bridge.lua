local _, AP = ...

-- Thin wrappers around the Auctionator internals this addon consumes.
-- Auctionator is a hard dependency, so everything here may assume it is
-- fully loaded; pcall stays where Auctionator can raise on bad input.
AP.Bridge = {}

local CallerID = AP.Constants.CallerID

-- Auctionator price-database key for an item link; nil when the link is unusable.
function AP.Bridge.DBKeyForLink(itemLink)
  if not itemLink then return nil end
  local ok, key = pcall(Auctionator.Utilities.BasicDBKeyFromLink, itemLink)
  if not ok then return nil end
  return key
end

-- Historical auction price from Auctionator's database; nil when unknown.
function AP.Bridge.AuctionPrice(itemLink)
  if not itemLink then return nil end
  local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, CallerID, itemLink)
  if ok and type(price) == "number" and price > 0 then return price end
  return nil
end

-- Days since the item was last seen at the auction house; nil when unknown.
function AP.Bridge.AuctionAge(itemLink)
  if not itemLink then return nil end
  local ok, age = pcall(Auctionator.API.v1.GetAuctionAgeByItemLink, CallerID, itemLink)
  if ok and type(age) == "number" and age >= 0 then return age end
  return nil
end

-- Subscribe a handler to Auctionator event-bus events. Returns the listener so
-- callers can register or unregister it for further events later.
function AP.Bridge.Listen(events, handler)
  local listener = { ReceiveEvent = handler }
  Auctionator.EventBus:Register(listener, events)
  return listener
end
