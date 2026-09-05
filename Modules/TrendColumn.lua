local _, AP = ...

-- Columns appended to Auctionator's listings; each stores a display string and a numeric sort key on every result entry
local TREND = { header = "Relative", text = "apTrendText", sort = "apTrendValue" }
local RATE = { header = "Sale Rate", text = "apRateText", sort = "apRateValue" }

-- Fund the columns from the flexible name column in the wide shopping listing; the narrow buy-auctions listing drops Auctionator's "You?" column instead (see wrapLayout opts)
local SHOPPING_COLUMNS = { { TREND, 62 }, { RATE, 60 } }
local BUY_COLUMNS = { { TREND, 58 } }

local NUMERIC_FIELDS = { [TREND.sort] = true, [RATE.sort] = true }

local function setTrendFields(entry, currentPrice, mode)
    -- The itemString resolves price history until the itemLink loads; gear falls back to base-item history until then
    local pct = AP.Trend.IndexFor(currentPrice, entry.itemLink or entry.itemString)
    entry[TREND.sort] = pct
    entry[TREND.text] = AP.Trend.Colorize(pct, mode) or ""
end

-- Region-wide sale rate from the TSM feed; blank without a figure
local function setRateFields(entry)
    local link = entry.itemLink or entry.itemString
    entry[RATE.sort] = AP.TSMFeed.SalePercentFor(link)
    entry[RATE.text] = AP.TSMFeed.SaleRateText(link) or ""
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

-- Append the columns once per provider, reshaping via private copies so Auctionator's shared layout stays untouched; opts.drop omits a column, opts.flex clears its fixed width
local function wrapLayout(mixin, columns, opts)
    local drop = opts and opts.drop
    local flex = opts and opts.flex
    local original = mixin.GetTableLayout
    mixin.GetTableLayout = function(self)
        if not self.apLayout then
            local merged = {}
            for _, column in ipairs(original(self)) do
                local field = column.cellParameters and column.cellParameters[1]
                if not (field and drop and drop[field]) then
                    if field and flex and flex[field] then
                        local resized = {}
                        for key, value in pairs(column) do resized[key] = value end
                        resized.width = nil
                        merged[#merged + 1] = resized
                    else
                        merged[#merged + 1] = column
                    end
                end
            end
            for _, pair in ipairs(columns) do
                merged[#merged + 1] = columnSpec(pair[1], pair[2])
            end
            self.apLayout = merged
        end
        return self.apLayout
    end
end

-- Sort our columns numerically with blanks last; every other field falls through to the original sort
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

local function isUnderSelling(frame)
    local node = frame
    while node do
        if node == _G.AuctionatorSellingFrame then return true end
        node = node:GetParent()
    end
    return false
end

-- Shopping results are a buyer's view: cheaper than average is good (green)
local function decorateShopping(_, entries)
    if type(entries) ~= "table" then return end
    for _, entry in ipairs(entries) do
        setTrendFields(entry, entry.minPrice, AP.Trend.UP_RED)
        setRateFields(entry)
    end
end

-- The current-prices listing is shared: seller's colours under the selling tab, buyer's colours in shopping browse, decided once per provider from its frame ancestry
local function decorateBuyAuctions(self)
    if type(self.currentResults) ~= "table" then return end
    if self.apMode == nil then
        self.apMode = isUnderSelling(self) and AP.Trend.UP_GREEN or AP.Trend.UP_RED
    end
    for _, entry in ipairs(self.currentResults) do
        setTrendFields(entry, entry.unitPrice, self.apMode)
    end
end

-- Auctionator's provider mixins exist at load time; the AH frames that copy them are created on first open
wrapLayout(AuctionatorShoppingTabDataProviderMixin, SHOPPING_COLUMNS)
wrapSort(AuctionatorShoppingTabDataProviderMixin)
hooksecurefunc(AuctionatorShoppingTabDataProviderMixin, "AddDetails", decorateShopping)

-- Re-decorate once item info loads (ProcessItemString) so suffixed gear refines from base-item to full-link history
hooksecurefunc(AuctionatorShoppingTabDataProviderMixin, "ProcessItemString", function(_, entry)
    setTrendFields(entry, entry.minPrice, AP.Trend.UP_RED)
    setRateFields(entry)
end)

-- Drop the "You?" column to fund the trend column so large prices are not clipped; "Available" flexes to absorb the freed width
wrapLayout(AuctionatorBuyAuctionsDataProviderMixin, BUY_COLUMNS, {
    drop = { isOwnedText = true },
    flex = { availablePretty = true },
})
wrapSort(AuctionatorBuyAuctionsDataProviderMixin)
hooksecurefunc(AuctionatorBuyAuctionsDataProviderMixin, "PopulateAuctions", decorateBuyAuctions)
