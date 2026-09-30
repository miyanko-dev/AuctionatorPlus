local _, AP = ...

-- Relative and Sale Rate columns for Auctionator's shopping results, the selling tab's current prices and the shopping buy screen of one item; each stores a display string and a numeric sort key on every result entry. The provider mixins exist at load time; the AH frames that copy them are created on first open

local TREND = { header = "Relative", text = "apTrendText", sort = "apTrendValue" }
local RATE = { header = "Sale Rate", text = "apRateText", sort = "apRateValue" }

local NUMERIC_FIELDS = { [TREND.sort] = true, [RATE.sort] = true }

-- Relative Value of price against the item's averages, in the colours of mode
local function setTrend(entry, price, itemRef, mode)
    local pct = AP.Trend.IndexFor(price, itemRef)
    entry[TREND.sort] = pct
    entry[TREND.text] = AP.Trend.Colorize(pct, mode) or ""
end

-- Region-wide TSM sale rate; blank without a figure
local function setRate(entry, itemRef)
    entry[RATE.sort] = AP.TSM.SalePercentFor(itemRef)
    entry[RATE.text] = AP.TSM.SaleRateText(itemRef) or ""
end

local function columnSpec(column, width)
    return {
        headerTemplate = "AuctionatorStringColumnHeaderTemplate",
        headerParameters = { column.sort },
        headerText = column.header,
        cellTemplate = "AuctionatorStringCellTemplate",
        cellParameters = { column.text },
        width = width,
    }
end

-- Append the columns once per provider through a private copy, so Auctionator's shared layout table stays untouched
local function wrapLayout(mixin, columns)
    local original = mixin.GetTableLayout
    mixin.GetTableLayout = function(self)
        if not self.apLayout then
            local merged = {}
            for _, column in ipairs(original(self)) do
                merged[#merged + 1] = column
            end
            for _, pair in ipairs(columns) do
                merged[#merged + 1] = columnSpec(pair[1], pair[2])
            end
            self.apLayout = merged
        end
        return self.apLayout
    end
end

-- Sort our columns numerically with blanks last; every other field falls through to the original sort, which has no comparator for ours
local function wrapSort(mixin)
    local original = mixin.Sort
    mixin.Sort = function(self, fieldName, sortDirection)
        if not NUMERIC_FIELDS[fieldName] then
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

local function decorateEach(priceField, mode, withRate)
    return function(_, entries)
        if type(entries) ~= "table" then return end
        for _, entry in ipairs(entries) do
            local itemRef = refFor(entry)
            setTrend(entry, entry[priceField], itemRef, mode)
            if withRate then setRate(entry, itemRef) end
        end
    end
end

-- Shopping results: a buyer's view, cheaper than average is good
wrapLayout(AuctionatorShoppingTabDataProviderMixin, { { TREND, 62 }, { RATE, 60 } })
wrapSort(AuctionatorShoppingTabDataProviderMixin)
hooksecurefunc(AuctionatorShoppingTabDataProviderMixin, "PrettifyData", decorateEach("minPrice", AP.Trend.UP_RED, true))

-- Selling tab current prices: a seller's view
wrapLayout(AuctionatorSearchDataProviderMixin, { { TREND, 62 } })
wrapSort(AuctionatorSearchDataProviderMixin)
hooksecurefunc(AuctionatorSearchDataProviderMixin, "AppendEntries", decorateEach("price", AP.Trend.UP_GREEN, false))

-- Shopping buy screen of one item: a buyer's view
wrapLayout(AuctionatorBuyItemDataProviderMixin, { { TREND, 62 } })
wrapSort(AuctionatorBuyItemDataProviderMixin)
hooksecurefunc(AuctionatorBuyItemDataProviderMixin, "AppendEntries", decorateEach("price", AP.Trend.UP_RED, false))
