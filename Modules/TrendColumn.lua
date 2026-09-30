local _, AP = ...

-- Relative column for Auctionator's shopping results, the selling tab's current prices and the shopping buy screen of one item; it stores a display string and a numeric sort key on every result entry. The provider mixins exist at load time; the AH frames that copy them are created on first open

-- Entry fields the column shows and sorts by
local TEXT_FIELD = "apTrendText"
local SORT_FIELD = "apTrendValue"

-- Relative Value of price against the item's averages, in the colours of mode
local function setTrend(entry, price, itemRef, mode)
    local pct = AP.Trend.IndexFor(price, itemRef)
    entry[SORT_FIELD] = pct
    entry[TEXT_FIELD] = AP.Trend.Colorize(pct, mode) or ""
end

-- Auctionator's listings only read their layout entries, so the three providers share one
local TREND_COLUMN = {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerParameters = { SORT_FIELD },
    headerText = "Relative",
    cellTemplate = "AuctionatorStringCellTemplate",
    cellParameters = { TEXT_FIELD },
    width = 62,
}

-- Append the column once per provider through a private copy, so Auctionator's shared layout table stays untouched
local function wrapLayout(mixin)
    local original = mixin.GetTableLayout
    mixin.GetTableLayout = function(self)
        if not self.apLayout then
            local merged = {}
            for _, column in ipairs(original(self)) do
                merged[#merged + 1] = column
            end
            merged[#merged + 1] = TREND_COLUMN
            self.apLayout = merged
        end
        return self.apLayout
    end
end

-- Sort our column numerically with blanks last; every other field falls through to the original sort, which has no comparator for ours
local function wrapSort(mixin)
    local original = mixin.Sort
    mixin.Sort = function(self, fieldName, sortDirection)
        if fieldName ~= SORT_FIELD then
            return original(self, fieldName, sortDirection)
        end
        local ascending = sortDirection == Auctionator.Constants.SORT.ASCENDING
        table.sort(self.results, function(a, b)
            local av, bv = a[fieldName], b[fieldName]
            if av == bv then
                return (a.sortingIndex or 0) < (b.sortingIndex or 0)
            end
            if av == nil then return false end
            if bv == nil then return true end
            if ascending then return av < bv end
            return av > bv
        end)
        self:SetDirty()
    end
end

-- Browse rows carry an item key, item rows a link and commodity rows only an item id
local function refFor(entry)
    if entry.itemLink then return entry.itemLink end
    if entry.itemKey then return entry.itemKey end
    if entry.itemID then return AP.Bridge.BaseItemKey(entry.itemID) end
    return nil
end

local function decorateEach(priceField, mode)
    return function(_, entries)
        if type(entries) ~= "table" then return end
        for _, entry in ipairs(entries) do
            setTrend(entry, entry[priceField], refFor(entry), mode)
        end
    end
end

-- Shopping results: a buyer's view, cheaper than average is good
wrapLayout(AuctionatorShoppingTabDataProviderMixin)
wrapSort(AuctionatorShoppingTabDataProviderMixin)
hooksecurefunc(AuctionatorShoppingTabDataProviderMixin, "PrettifyData", decorateEach("minPrice", AP.Trend.UP_RED))

-- Selling tab current prices: a seller's view
wrapLayout(AuctionatorSearchDataProviderMixin)
wrapSort(AuctionatorSearchDataProviderMixin)
hooksecurefunc(AuctionatorSearchDataProviderMixin, "AppendEntries", decorateEach("price", AP.Trend.UP_GREEN))

-- Shopping buy screen of one item: a buyer's view
wrapLayout(AuctionatorBuyItemDataProviderMixin)
wrapSort(AuctionatorBuyItemDataProviderMixin)
hooksecurefunc(AuctionatorBuyItemDataProviderMixin, "AppendEntries", decorateEach("price", AP.Trend.UP_RED))
