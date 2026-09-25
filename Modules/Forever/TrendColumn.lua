local _, AP = ...

-- Forever half of the columns: Auctionator's ModernAH shopping results, the selling tab's current prices and the shopping buy screen of one item. The provider mixins exist at load time; the AH frames that copy them are created on first open
local Column = AP.TrendColumn

-- Browse rows carry an item key, item rows a link and commodity rows only an item id
local function refFor(entry)
    if entry.itemLink then return entry.itemLink end
    if entry.itemKey then return entry.itemKey end
    if entry.itemID then return AP.Bridge.BaseItemKey(entry.itemID) end
    return nil
end

local function decorateEach(priceField, mode, withRate)
    return function(_, entries)
        if type(entries) ~= "table" then return end
        for _, entry in ipairs(entries) do
            local itemRef = refFor(entry)
            Column.SetTrend(entry, entry[priceField], itemRef, mode)
            if withRate then Column.SetRate(entry, itemRef) end
        end
    end
end

-- Shopping results: a buyer's view, cheaper than average is good
Column.WrapLayout(AuctionatorShoppingTabDataProviderMixin, { { Column.TREND, 62 }, { Column.RATE, 60 } })
Column.WrapSort(AuctionatorShoppingTabDataProviderMixin)
hooksecurefunc(AuctionatorShoppingTabDataProviderMixin, "PrettifyData", decorateEach("minPrice", AP.Trend.UP_RED, true))

-- Selling tab current prices: a seller's view
Column.WrapLayout(AuctionatorSearchDataProviderMixin, { { Column.TREND, 62 } })
Column.WrapSort(AuctionatorSearchDataProviderMixin)
hooksecurefunc(AuctionatorSearchDataProviderMixin, "AppendEntries", decorateEach("price", AP.Trend.UP_GREEN, false))

-- Shopping buy screen of one item: a buyer's view
Column.WrapLayout(AuctionatorBuyItemDataProviderMixin, { { Column.TREND, 62 } })
Column.WrapSort(AuctionatorBuyItemDataProviderMixin)
hooksecurefunc(AuctionatorBuyItemDataProviderMixin, "AppendEntries", decorateEach("price", AP.Trend.UP_RED, false))
