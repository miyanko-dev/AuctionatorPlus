local _, AP = ...

-- Era half of the columns: Auctionator's LegacyAH shopping list and its buy-auctions listing, which serves the selling tab and the shopping buy screen alike
local Column = AP.TrendColumn

-- The wide shopping listing funds the columns from its flexible name column; the narrow buy-auctions listing drops Auctionator's "You?" column instead
local SHOPPING_COLUMNS = { { Column.TREND, 62 }, { Column.RATE, 60 } }
local BUY_COLUMNS = { { Column.TREND, 58 } }

-- The itemString resolves price history until the itemLink loads; gear falls back to base-item history until then
local function refFor(entry)
    return entry.itemLink or entry.itemString
end

local function isUnderSelling(frame)
    local node = frame
    while node do
        if node == AuctionatorSellingFrame then return true end
        node = node:GetParent()
    end
    return false
end

-- Shopping results are a buyer's view: cheaper than average is good
local function decorateShopping(_, entries)
    if type(entries) ~= "table" then return end
    for _, entry in ipairs(entries) do
        Column.SetTrend(entry, entry.minPrice, refFor(entry), AP.Trend.UP_RED)
        Column.SetRate(entry, refFor(entry))
    end
end

-- The buy-auctions listing is shared: seller's colours under the selling tab, buyer's colours on the shopping buy screen, decided once per provider from its frame ancestry
local function decorateBuyAuctions(self)
    if type(self.currentResults) ~= "table" then return end
    if self.apMode == nil then
        self.apMode = isUnderSelling(self) and AP.Trend.UP_GREEN or AP.Trend.UP_RED
    end
    for _, entry in ipairs(self.currentResults) do
        Column.SetTrend(entry, entry.unitPrice, entry.itemLink, self.apMode)
    end
end

-- Auctionator's provider mixins exist at load time; the AH frames that copy them are created on first open
Column.WrapLayout(AuctionatorShoppingTabDataProviderMixin, SHOPPING_COLUMNS)
Column.WrapSort(AuctionatorShoppingTabDataProviderMixin)
hooksecurefunc(AuctionatorShoppingTabDataProviderMixin, "AddDetails", decorateShopping)

-- Re-decorate once item info loads, so suffixed gear refines from base-item to full-link history
hooksecurefunc(AuctionatorShoppingTabDataProviderMixin, "ProcessItemString", function(_, entry)
    Column.SetTrend(entry, entry.minPrice, refFor(entry), AP.Trend.UP_RED)
    Column.SetRate(entry, refFor(entry))
end)

-- "Available" flexes to absorb the width the dropped "You?" column frees, so large prices are not clipped
Column.WrapLayout(AuctionatorBuyAuctionsDataProviderMixin, BUY_COLUMNS, {
    drop = { isOwnedText = true },
    flex = { availablePretty = true },
})
Column.WrapSort(AuctionatorBuyAuctionsDataProviderMixin)
hooksecurefunc(AuctionatorBuyAuctionsDataProviderMixin, "PopulateAuctions", decorateBuyAuctions)
