local _, AP = ...

local TREND_HEADER     = "Trend"
local TREND_TEXT_FIELD = "auctionatorPlusTrendText"  -- coloured string (display)
local TREND_SORT_FIELD = "auctionatorPlusTrendValue" -- number (sort + CSV)

-- Shopping results have a wide listing; the buy-auctions listing (selling
-- current prices, shopping browse) is narrower, so its column is slimmer and we
-- reclaim space from its oversized "Available" column (a stack count needs far
-- less than 120px) to keep the adjacent fill "You?" column readable.
local SHOPPING_WIDTH  = 70
local BUY_WIDTH       = 56
local AVAILABLE_FIELD = "availablePretty"
local AVAILABLE_WIDTH = 70

local function SetTrendFields(entry, currentPrice, mode)
  local average = AP.Trend.AverageFor(entry.itemLink)
  local pct = AP.Trend.Percent(currentPrice, average)
  if pct == nil then
    entry[TREND_SORT_FIELD] = nil
    entry[TREND_TEXT_FIELD] = ""
  else
    entry[TREND_SORT_FIELD] = pct
    entry[TREND_TEXT_FIELD] = AP.Trend.Colorize(pct, mode)
  end
end

-- Append the trend column to a provider's layout, once, caching the merged
-- layout on the instance so repeat GetTableLayout calls stay stable. When
-- narrowField is given, the existing column carrying that cellParameter is
-- shrunk to narrowWidth via a private copy, leaving Auctionator's shared layout
-- untouched, to free room for the trend column.
local function WrapLayout(mixin, width, narrowField, narrowWidth)
  local original = mixin.GetTableLayout
  mixin.GetTableLayout = function(self)
    if not self.auctionatorPlusLayout then
      local merged = {}
      for index, column in ipairs(original(self)) do
        if narrowField and column.cellParameters
            and column.cellParameters[1] == narrowField then
          local resized = {}
          for key, value in pairs(column) do resized[key] = value end
          resized.width = narrowWidth
          merged[index] = resized
        else
          merged[index] = column
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

-- Teach the provider's Sort about the trend column (numeric, blanks last);
-- every other field falls through to the original comparator-based sort.
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

-- The current-prices listing is shared: the selling tab is a seller's view
-- (dearer is good, green); the shopping browse panel is a buyer's view (cheaper
-- is good, green). Decide once per provider from its frame ancestry.
local function DecorateBuyAuctions(self)
  if type(self.currentResults) ~= "table" then return end
  if self.auctionatorPlusMode == nil then
    self.auctionatorPlusMode = IsUnderSelling(self) and AP.Trend.UP_GREEN or AP.Trend.UP_RED
  end
  for _, entry in ipairs(self.currentResults) do
    SetTrendFields(entry, entry.unitPrice, self.auctionatorPlusMode)
  end
end

-- Auctionator is a hard dependency, so its provider mixins exist at load time;
-- the AH frames that copy them are created later (on first open).
WrapLayout(AuctionatorShoppingTabDataProviderMixin, SHOPPING_WIDTH)
WrapSort(AuctionatorShoppingTabDataProviderMixin)
hooksecurefunc(AuctionatorShoppingTabDataProviderMixin, "AddDetails", DecorateShopping)

WrapLayout(AuctionatorBuyAuctionsDataProviderMixin, BUY_WIDTH, AVAILABLE_FIELD, AVAILABLE_WIDTH)
WrapSort(AuctionatorBuyAuctionsDataProviderMixin)
hooksecurefunc(AuctionatorBuyAuctionsDataProviderMixin, "PopulateAuctions", DecorateBuyAuctions)
