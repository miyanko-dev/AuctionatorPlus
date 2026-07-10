local _, AP = ...

local TREND_HEADER     = "Trend"
local TREND_TEXT_FIELD = "auctionatorPlusTrendText"  -- coloured string (display)
local TREND_SORT_FIELD = "auctionatorPlusTrendValue" -- number (sort + CSV)

-- Trend column width per listing. The shopping results listing is wide, so its
-- trend column simply shrinks the flexible name column. The buy-auctions listing
-- (selling current prices, shopping browse) is narrow, so its trend column is
-- funded by dropping Auctionator's low-value "You?" column (see WrapLayout call).
local SHOPPING_TREND_WIDTH = 70
local BUY_TREND_WIDTH      = 45

local function SetTrendFields(entry, currentPrice, mode)
  -- Shopping entries only get itemLink once their item info has loaded; the
  -- itemString they carry from the start resolves the price history just as
  -- well (gear falls back to its base-item history until the link arrives).
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

-- Append the trend column to a provider's layout, once, caching the merged
-- layout on the instance so repeat GetTableLayout calls stay stable. Opts, keyed
-- by a column's cell field, reshape Auctionator's columns via private copies so
-- its shared layout stays untouched: opts.drop omits a column, opts.flex clears
-- a column's fixed width so it stretches to fill the freed space.
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
WrapLayout(AuctionatorShoppingTabDataProviderMixin, SHOPPING_TREND_WIDTH)
WrapSort(AuctionatorShoppingTabDataProviderMixin)
hooksecurefunc(AuctionatorShoppingTabDataProviderMixin, "AddDetails", DecorateShopping)

-- Once an entry's item info loads, Auctionator fills in its itemLink and
-- repaints (ProcessItemString); re-decorating there refines the trend with the
-- full link — for suffixed gear the itemString only reaches the base item.
hooksecurefunc(AuctionatorShoppingTabDataProviderMixin, "ProcessItemString", function(_, entry)
  SetTrendFields(entry, entry.minPrice, AP.Trend.UP_RED)
end)

-- Drop the "You?" column (just a "Yes" flag on your own auctions) to fund the
-- trend column, so unit/stack price keep Auctionator's native 145px and large
-- prices are not clipped. "Available" then flexes to absorb the freed width.
WrapLayout(AuctionatorBuyAuctionsDataProviderMixin, BUY_TREND_WIDTH, {
  drop = { isOwnedText = true },
  flex = { availablePretty = true },
})
WrapSort(AuctionatorBuyAuctionsDataProviderMixin)
hooksecurefunc(AuctionatorBuyAuctionsDataProviderMixin, "PopulateAuctions", DecorateBuyAuctions)

-- Re-derive the trend fields of everything currently listed and repaint; used
-- by TSMTrend.lua when the trend baseline source toggles.
function AP.RepaintTrendColumns()
  local shoppingFrame = _G.AuctionatorShoppingFrame
  local shoppingProvider = shoppingFrame and shoppingFrame.DataProvider
  if shoppingProvider and type(shoppingProvider.results) == "table" then
    DecorateShopping(shoppingProvider, shoppingProvider.results)
    shoppingProvider:SetDirty()
  end

  local buyFrames = {}
  if _G.AuctionatorSellingFrame and _G.AuctionatorSellingFrame.BuyFrame then
    table.insert(buyFrames, _G.AuctionatorSellingFrame.BuyFrame)
  end
  if _G.AuctionatorBuyFrame then
    table.insert(buyFrames, _G.AuctionatorBuyFrame)
  end
  for _, buyFrame in ipairs(buyFrames) do
    local provider = buyFrame.CurrentPrices and buyFrame.CurrentPrices.SearchDataProvider
    if provider and type(provider.currentResults) == "table" then
      DecorateBuyAuctions(provider)
      provider:SetDirty()
    end
  end
end
