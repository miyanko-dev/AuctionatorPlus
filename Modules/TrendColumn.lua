local _, AP = ...

local TREND_HEADER     = "Rel. Value"
local TREND_TEXT_FIELD = "auctionatorPlusTrendText"  -- coloured string (display)
local TREND_SORT_FIELD = "auctionatorPlusTrendValue" -- number (sort + CSV)

-- Fund the column from the flexible name column in the wide shopping listing; the narrow buy-auctions listing drops Auctionator's "You?" column instead (see WrapLayout opts).
local SHOPPING_TREND_WIDTH = 70
local BUY_TREND_WIDTH      = 55

local function SetTrendFields(entry, currentPrice, mode)
  -- The itemString resolves price history until the itemLink loads; gear falls back to base-item history until then.
  local average = AP.Trend.AverageFor(entry.itemLink or entry.itemString)
  local pct = AP.Trend.Percent(currentPrice, average)
  if pct == nil then
    entry[TREND_SORT_FIELD] = nil
    entry[TREND_TEXT_FIELD] = ""
  else
    entry[TREND_SORT_FIELD] = pct
    entry[TREND_TEXT_FIELD] = AP.Trend.Colorize(pct, mode)
  end
end

-- Append the trend column once per provider, reshaping columns via private copies so Auctionator's shared layout stays untouched; opts.drop omits a column, opts.flex clears its fixed width.
local function WrapLayout(mixin, width, opts)
  local drop = opts and opts.drop
  local flex = opts and opts.flex
  local original = mixin.GetTableLayout
  mixin.GetTableLayout = function(self)
    if not self.auctionatorPlusLayout then
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
      merged[#merged + 1] = {
        headerTemplate = "AuctionatorStringColumnHeaderTemplate",
        headerParameters = { TREND_SORT_FIELD },
        headerText = TREND_HEADER,
        cellTemplate = "AuctionatorStringCellTemplate",
        cellParameters = { TREND_TEXT_FIELD },
        width = width,
      }
      self.auctionatorPlusLayout = merged
    end
    return self.auctionatorPlusLayout
  end
end

-- Sort the trend column numerically with blanks last; every other field falls through to the original sort.
local function WrapSort(mixin)
  local original = mixin.Sort
  mixin.Sort = function(self, fieldName, sortDirection)
    if fieldName ~= TREND_SORT_FIELD then
      return original(self, fieldName, sortDirection)
    end
    local ascending = sortDirection == Auctionator.Constants.SORT.ASCENDING
    table.sort(self.results, function(a, b)
      local av, bv = a[TREND_SORT_FIELD], b[TREND_SORT_FIELD]
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

local function IsUnderSelling(frame)
  local node = frame
  while node do
    if node == _G.AuctionatorSellingFrame then return true end
    node = node:GetParent()
  end
  return false
end

-- Shopping results are a buyer's view: cheaper than average is good (green).
local function DecorateShopping(_, entries)
  if type(entries) ~= "table" then return end
  for _, entry in ipairs(entries) do
    SetTrendFields(entry, entry.minPrice, AP.Trend.UP_RED)
  end
end

-- The current-prices listing is shared: seller's colours under the selling tab, buyer's colours in shopping browse, decided once per provider from its frame ancestry.
local function DecorateBuyAuctions(self)
  if type(self.currentResults) ~= "table" then return end
  if self.auctionatorPlusMode == nil then
    self.auctionatorPlusMode = IsUnderSelling(self) and AP.Trend.UP_GREEN or AP.Trend.UP_RED
  end
  for _, entry in ipairs(self.currentResults) do
    SetTrendFields(entry, entry.unitPrice, self.auctionatorPlusMode)
  end
end

-- Auctionator's provider mixins exist at load time; the AH frames that copy them are created on first open.
WrapLayout(AuctionatorShoppingTabDataProviderMixin, SHOPPING_TREND_WIDTH)
WrapSort(AuctionatorShoppingTabDataProviderMixin)
hooksecurefunc(AuctionatorShoppingTabDataProviderMixin, "AddDetails", DecorateShopping)

-- Re-decorate once item info loads (ProcessItemString) so suffixed gear refines from base-item to full-link history.
hooksecurefunc(AuctionatorShoppingTabDataProviderMixin, "ProcessItemString", function(_, entry)
  SetTrendFields(entry, entry.minPrice, AP.Trend.UP_RED)
end)

-- Drop the "You?" column to fund the trend column so large prices are not clipped; "Available" flexes to absorb the freed width.
WrapLayout(AuctionatorBuyAuctionsDataProviderMixin, BUY_TREND_WIDTH, {
  drop = { isOwnedText = true },
  flex = { availablePretty = true },
})
WrapSort(AuctionatorBuyAuctionsDataProviderMixin)
hooksecurefunc(AuctionatorBuyAuctionsDataProviderMixin, "PopulateAuctions", DecorateBuyAuctions)
