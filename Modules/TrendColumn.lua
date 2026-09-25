local _, AP = ...

-- Relative and Sale Rate columns for Auctionator's listings; each stores a display string and a numeric sort key on every result entry. Each client's half wires them into its own data providers
AP.TrendColumn = {}

local TREND = { header = "Relative", text = "apTrendText", sort = "apTrendValue" }
local RATE = { header = "Sale Rate", text = "apRateText", sort = "apRateValue" }
AP.TrendColumn.TREND = TREND
AP.TrendColumn.RATE = RATE

local NUMERIC_FIELDS = { [TREND.sort] = true, [RATE.sort] = true }

-- Relative Value of price against the item's averages, in the colours of mode
function AP.TrendColumn.SetTrend(entry, price, itemRef, mode)
    local pct = AP.Trend.IndexFor(price, itemRef)
    entry[TREND.sort] = pct
    entry[TREND.text] = AP.Trend.Colorize(pct, mode) or ""
end

-- Region-wide TSM sale rate; blank without a figure
function AP.TrendColumn.SetRate(entry, itemRef)
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

-- A copy of an Auctionator column without its fixed width, so it flexes to absorb freed space
local function flexCopy(column)
    local resized = {}
    for key, value in pairs(column) do resized[key] = value end
    resized.width = nil
    return resized
end

-- Append the columns once per provider through a private copy, so Auctionator's shared layout table stays untouched; opts.drop omits Auctionator columns and opts.flex clears their fixed width, both keyed by cell field
function AP.TrendColumn.WrapLayout(mixin, columns, opts)
    local drop = opts and opts.drop or {}
    local flex = opts and opts.flex or {}
    local original = mixin.GetTableLayout
    mixin.GetTableLayout = function(self)
        if not self.apLayout then
            local merged = {}
            for _, column in ipairs(original(self)) do
                local field = column.cellParameters and column.cellParameters[1]
                if not (field and drop[field]) then
                    merged[#merged + 1] = (field and flex[field]) and flexCopy(column) or column
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

-- Sort our columns numerically with blanks last; every other field falls through to the original sort, which has no comparator for ours
function AP.TrendColumn.WrapSort(mixin)
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
