local _, AP = ...

-- Era half of the bridge: Auctionator's LegacyAH build, where items are links or item strings and one scanner serves a single query at a time

-- Price-database keys, most specific first (suffix key, then base item); the legacy build answers at once, so nil only for an unusable reference
function AP.Bridge.DBKeys(itemRef)
    if type(itemRef) ~= "string" or itemRef == "" then return nil end
    return AP.Bridge.KeysForLink(itemRef)
end

-- Link with enchant and gems blanked, the key Auctionator files auctions under; "" when the link is unusable
function AP.Bridge.CleanLink(itemLink)
    local ok, clean = pcall(Auctionator.Search.GetCleanItemLink, itemLink)
    return ok and clean or ""
end

-- Start a query on the shared scanner; false when another search holds it
function AP.Bridge.Query(query)
    return (pcall(Auctionator.AH.QueryAuctionItems, query))
end

function AP.Bridge.AbortQuery()
    Auctionator.AH.AbortQuery()
end

function AP.Bridge.IsNotThrottled()
    return Auctionator.AH.IsNotThrottled()
end

-- Record scan results in the price database the way Auctionator's own searches do
function AP.Bridge.RecordResults(entries)
    Auctionator.Search.GroupResultsForDB(entries)
end

-- Auctionator's own shopping-list progress line ("Search for item X/Y in ...")
function AP.Bridge.SearchStatus(done, total, listName)
    return Auctionator.Locales.Apply("LIST_SEARCH_STATUS", done, total, listName)
end

-- Set the sale price to an exact amount through the event Auctionator's own price-history rows fire, which skips its undercut
function AP.Bridge.SelectPrice(price)
    AP.Bridge.Fire(Auctionator.Buying.Events.HistoricalPrice, price)
end

-- Item link of a shopping result, taken from its first auction; nil for missing-term placeholders
function AP.Bridge.ShoppingItemRef(entry)
    local first = entry.entries and entry.entries[1]
    return first and first.itemLink
end
