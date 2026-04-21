local ADDON_NAME = ...

local PRICE_JUMP_RATIO = 1.20
local SCAN_TIMEOUT_SECONDS = 6
local AH_CUT = 0.05

local PANEL_WIDTH = 800
local PANEL_HEIGHT = 500
local ROW_HEIGHT = 28

FF = {}
FF.flips = {}
FF.panel = nil
FF.collected = {}
FF.seenKeys = {}
FF.listingsCache = {}
FF.committedRatio = PRICE_JUMP_RATIO
FF.committedMaxInvest = 0
FF.committedMinQuantity = 0
FF.committedMinOrderQty = 0

local function KeyString(itemKey)
  return Auctionator.Utilities.ItemKeyString(itemKey)
end

local function CollectCommodityListings(itemID)
  local listings = {}
  local total = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0

  for index = 1, total do
    local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
    if info and info.unitPrice and info.unitPrice > 0 then
      local quantity = info.quantity or 1
      if quantity < 1 then
        quantity = 1
      end
      table.insert(listings, {
        unitPrice = info.unitPrice,
        cost = info.unitPrice * quantity,
      })
    end
  end

  return listings
end

local function CollectItemListings(itemKey)
  local listings = {}
  local total = C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0

  for index = 1, total do
    local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
    if info and info.buyoutAmount and info.buyoutAmount > 0 then
      local quantity = info.quantity or 1
      if quantity < 1 then
        quantity = 1
      end
      table.insert(listings, {
        unitPrice = info.buyoutAmount / quantity,
        cost = info.buyoutAmount,
      })
    end
  end

  return listings
end

local function FindFlipBrackets(listings, ratio)
  table.sort(listings, function(a, b) return a.unitPrice < b.unitPrice end)

  for i = 2, #listings do
    local priceRatio = listings[i].unitPrice / listings[i - 1].unitPrice
    if priceRatio >= ratio then
      local flipListings = {}
      for j = 1, i - 1 do
        flipListings[j] = listings[j]
      end
      return flipListings, listings[i].unitPrice
    end
  end

  return nil, nil
end

local function SummarizeFlip(flipListings, topPrice)
  local totalCost = 0
  local totalQuantity = 0

  for _, listing in ipairs(flipListings) do
    local quantity = listing.cost / listing.unitPrice
    totalCost = totalCost + listing.cost
    totalQuantity = totalQuantity + quantity
  end

  local potentialProfit = totalQuantity * topPrice * (1 - AH_CUT) - totalCost

  return {
    topPrice = topPrice,
    margin = potentialProfit,
    totalCost = totalCost,
    totalQuantity = totalQuantity,
  }
end

function FF:ResetState()
  self:AbortScan()
  self.collected = {}
  self.seenKeys = {}
end

function FF:CollectEntries(entries)
  if type(entries) ~= "table" then
    return
  end
  for _, entry in ipairs(entries) do
    if entry and entry.itemKey and entry.totalQuantity and entry.totalQuantity > 0 then
      local key = KeyString(entry.itemKey)
      if not self.seenKeys[key] then
        self.seenKeys[key] = true
        table.insert(self.collected, entry)
      end
    end
  end
end

function FF:AbortScan()
  if self.currentTimeout then
    self.currentTimeout:Cancel()
    self.currentTimeout = nil
  end
  self.scanning = false
  self.currentEntry = nil
  self.currentKey = nil
  self.currentIsCommodity = nil
  self.scanQueue = {}
end

function FF:StartScan()
  self:AbortScan()
  self:CommitFilters()

  self.flips = {}
  self.listingsCache = {}
  self.scannedCount = 0

  for _, entry in ipairs(self.collected) do
    table.insert(self.scanQueue, entry)
  end

  self.totalToScan = #self.scanQueue

  if self.totalToScan == 0 then
    if self.panel then
      self.panel:SetStatus("Run a shopping list search first.")
      self.panel:Render()
    end
    return
  end

  self.scanning = true

  if self.panel then
    self.panel:SetStatus(string.format("Scanning: 0 / %d (0%%)", self.totalToScan))
    self.panel:Render()
  end

  self:ScanNext()
end

function FF:ScanNext()
  if not self.scanning then
    return
  end

  if self.currentTimeout then
    self.currentTimeout:Cancel()
    self.currentTimeout = nil
  end

  if #self.scanQueue == 0 then
    self.scanning = false
    self.currentEntry = nil
    self.currentKey = nil
    self.currentIsCommodity = nil

    if self.panel then
      local found = #self.flips
      if found > 0 then
        self.panel:SetStatus(string.format("Scan complete. %d flip(s) found.", found))
      else
        self.panel:SetStatus("Scan complete. No flips found.")
      end
      self.panel:Render()
    end

    return
  end

  local entry = table.remove(self.scanQueue, 1)
  self.currentEntry = entry
  self.currentKey = KeyString(entry.itemKey)
  self.currentIsCommodity = nil

  if self.panel then
    local pct = math.floor((self.scannedCount / self.totalToScan) * 100 + 0.5)
    self.panel:SetStatus(string.format(
      "Scanning: %d / %d (%d%%)", self.scannedCount + 1, self.totalToScan, pct
    ))
  end

  local myKey = self.currentKey
  Auctionator.AH.GetItemKeyInfo(entry.itemKey, function(itemKeyInfo)
    if not self.scanning or self.currentKey ~= myKey then
      return
    end

    if not itemKeyInfo then
      self.scannedCount = self.scannedCount + 1
      self:ScanNext()
      return
    end

    self.currentIsCommodity = itemKeyInfo.isCommodity == true
    self:FireQuery()
  end)
end

function FF:FireQuery()
  if not self.scanning or not self.currentEntry then
    return
  end

  local entry = self.currentEntry
  local expectedKey = self.currentKey

  self.currentTimeout = C_Timer.NewTimer(SCAN_TIMEOUT_SECONDS, function()
    if self.currentKey == expectedKey then
      self.scannedCount = self.scannedCount + 1
      self:ScanNext()
    end
  end)

  if self.currentIsCommodity then
    Auctionator.AH.SendSearchQueryByItemKey(
      entry.itemKey,
      Auctionator.Constants.CommodityResultsSorts,
      false
    )
  else
    Auctionator.AH.SendSearchQueryByItemKey(
      entry.itemKey,
      { Auctionator.Constants.ItemResultsSorts },
      true
    )
  end
end

function FF:HandleScanResult(itemKeyOrID)
  if not self.scanning or not self.currentEntry then
    return
  end

  local expectedKey = self.currentEntry.itemKey
  local matches = false

  if type(itemKeyOrID) == "number" then
    matches = expectedKey.itemID == itemKeyOrID
  elseif type(itemKeyOrID) == "table" then
    matches = KeyString(itemKeyOrID) == self.currentKey
  end

  if not matches then
    return
  end

  local listings
  if self.currentIsCommodity then
    listings = CollectCommodityListings(expectedKey.itemID)
  else
    listings = CollectItemListings(expectedKey)
  end

  self.listingsCache[self.currentKey] = {
    listings = listings,
    entry = self.currentEntry,
  }

  local previousCount = #self.flips
  self:ComputeFlipForItem(self.currentKey)
  if #self.flips > previousCount and self.panel then
    self.panel:Render()
  end

  self.scannedCount = self.scannedCount + 1
  self:ScanNext()
end

function FF:ReceiveEvent(eventName, eventData, ...)
  if eventName == Auctionator.Shopping.Tab.Events.SearchStart then
    self:ResetState()

  elseif eventName == Auctionator.Shopping.Tab.Events.SearchIncrementalUpdate then
    self:CollectEntries(eventData)

  elseif eventName == Auctionator.Shopping.Tab.Events.SearchEnd then
    self:CollectEntries(eventData)

  elseif eventName == Auctionator.Buying.Events.ShowCommodityBuy
      or eventName == Auctionator.Buying.Events.ShowItemBuy then
    self:AbortScan()

  elseif eventName == Auctionator.AH.Events.CommoditySearchResultsReady then
    if self.currentIsCommodity == true then
      self:HandleScanResult(eventData)
    end

  elseif eventName == Auctionator.AH.Events.ItemSearchResultsReady then
    if self.currentIsCommodity == false then
      self:HandleScanResult(eventData)
    end
  end
end

local function RegisterEventBus()
  if FF.registered then
    return
  end
  if not (Auctionator and Auctionator.EventBus and Auctionator.AH and Auctionator.AH.Events
      and Auctionator.Shopping and Auctionator.Shopping.Tab and Auctionator.Buying) then
    return
  end
  FF.registered = true

  Auctionator.EventBus:RegisterSource(FF, "FlipFinder")
  Auctionator.EventBus:Register(FF, {
    Auctionator.Shopping.Tab.Events.SearchStart,
    Auctionator.Shopping.Tab.Events.SearchEnd,
    Auctionator.Shopping.Tab.Events.SearchIncrementalUpdate,
    Auctionator.Buying.Events.ShowCommodityBuy,
    Auctionator.Buying.Events.ShowItemBuy,
    Auctionator.AH.Events.CommoditySearchResultsReady,
    Auctionator.AH.Events.ItemSearchResultsReady,
  })
end

function FF:CommitFilters()
  if not self.panel then
    return
  end

  local pct = tonumber(self.panel.MinMarginEditBox:GetText())
  if pct and pct > 0 then
    self.committedRatio = 1 + (pct / 100)
  else
    self.committedRatio = PRICE_JUMP_RATIO
  end

  local gold = tonumber(self.panel.MaxInvestEditBox:GetText())
  if gold and gold > 0 then
    self.committedMaxInvest = gold * 10000
  else
    self.committedMaxInvest = 0
  end

  local qty = tonumber(self.panel.MinQuantityEditBox:GetText())
  if qty and qty > 0 then
    self.committedMinQuantity = qty
  else
    self.committedMinQuantity = 0
  end

  local orderQty = tonumber(self.panel.MinOrderQtyEditBox:GetText())
  if orderQty and orderQty > 0 then
    self.committedMinOrderQty = orderQty
  else
    self.committedMinOrderQty = 0
  end
end

function FF:ComputeFlipForItem(key)
  local cached = self.listingsCache and self.listingsCache[key]
  if not cached then
    return
  end

  local flipListings, topPrice = FindFlipBrackets(cached.listings, self.committedRatio)
  if not flipListings or not topPrice then
    return
  end

  local summary = SummarizeFlip(flipListings, topPrice)
  if self.committedMaxInvest > 0 and summary.totalCost > self.committedMaxInvest then
    return
  end
  if self.committedMinQuantity > 0 and cached.entry.totalQuantity < self.committedMinQuantity then
    return
  end
  if self.committedMinOrderQty > 0 and summary.totalQuantity < self.committedMinOrderQty then
    return
  end

  table.insert(self.flips, {
    itemKey = cached.entry.itemKey,
    itemLink = cached.entry.itemLink,
    itemName = cached.entry.itemName,
    topPrice = summary.topPrice,
    margin = summary.margin,
    totalCost = summary.totalCost,
    totalQuantity = summary.totalQuantity,
    displayQuantity = cached.entry.totalQuantity,
  })
end

function FF:RebuildFlips()
  self:CommitFilters()

  self.flips = {}
  for key in pairs(self.listingsCache) do
    self:ComputeFlipForItem(key)
  end

  if self.panel then
    self.panel:Render()
  end
end

function FF:OpenItemDetails(flip)
  local term

  if flip.itemLink then
    local name = GetItemInfo(flip.itemLink)
    if name and name ~= "" then
      term = name
    end
  end

  if not term or term == "" then
    term = flip.itemName
  end

  if not term or term == "" then
    return
  end

  if type(term) ~= "string" then
    return
  end

  term = string.gsub(term, "|c[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]", "")
  term = string.gsub(term, "|C[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]", "")
  term = string.gsub(term, "|r", "")
  term = string.gsub(term, "|R", "")
  term = string.gsub(term, "|H[^|]+|h", "")
  term = string.gsub(term, "|h", "")
  term = string.gsub(term, "|T.-|t", "")
  term = string.gsub(term, "|t", "")
  term = string.gsub(term, "|A.-|a", "")
  term = string.gsub(term, "|a", "")
  term = string.gsub(term, "%s+", " ")
  term = strtrim(term)

  if term == "" or term == nil then
    return
  end

  local ok = pcall(Auctionator.API.v1.MultiSearchExact, "FlipFinder", { term })
  if not ok then
    pcall(Auctionator.API.v1.MultiSearch, "FlipFinder", { term })
  end
end

local function FormatGold(copper)
  if not copper or copper <= 0 then
    return "0g"
  end

  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)

  if g > 0 and s > 0 then
    return string.format("%dg %ds", g, s)
  elseif g > 0 then
    return string.format("%dg", g)
  else
    return string.format("%ds", s)
  end
end

local tooltipBackdrop = {
  bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile     = true,
  tileSize = 8,
  edgeSize = 16,
  insets   = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function applyTooltipStyle(frame)
  frame:SetBackdrop(tooltipBackdrop)
  frame:SetBackdropColor(0.06, 0.06, 0.06, 0.97)
  frame:SetBackdropBorderColor(0.8, 0.8, 0.8, 0.9)
end

local COL_ITEM_W   = 220
local COL_QTY_W    = 90
local COL_ORDER_W  = 90
local COL_COST_W   = 90
local COL_PROFIT_W = 100
local COL_BTN_W    = 100
local COL_GAP      = 8

local function CreateRow(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
  row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)

  local sep = row:CreateTexture(nil, "ARTWORK")
  sep:SetHeight(1)
  sep:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
  sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  sep:SetColorTexture(0.8, 0.8, 0.8, 0.08)

  row.Item = CreateFrame("Button", nil, row)
  row.Item:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.Item:SetSize(COL_ITEM_W, ROW_HEIGHT)
  row.Item.Text = row.Item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.Item.Text:SetPoint("LEFT", 0, 0)
  row.Item.Text:SetPoint("RIGHT", -4, 0)
  row.Item.Text:SetJustifyH("LEFT")
  row.Item.Text:SetWordWrap(false)

  local qtyX = COL_ITEM_W + COL_GAP
  row.Quantity = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.Quantity:SetPoint("LEFT", qtyX, 0)
  row.Quantity:SetWidth(COL_QTY_W)
  row.Quantity:SetJustifyH("LEFT")

  local costX = qtyX + COL_QTY_W + COL_GAP
  row.TotalCost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.TotalCost:SetPoint("LEFT", costX, 0)
  row.TotalCost:SetWidth(COL_COST_W)
  row.TotalCost:SetJustifyH("LEFT")

  local orderX = costX + COL_COST_W + COL_GAP
  row.OrderQty = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.OrderQty:SetPoint("LEFT", orderX, 0)
  row.OrderQty:SetWidth(COL_ORDER_W)
  row.OrderQty:SetJustifyH("LEFT")

  local profitX = orderX + COL_ORDER_W + COL_GAP
  row.Profit = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.Profit:SetPoint("LEFT", profitX, 0)
  row.Profit:SetWidth(COL_PROFIT_W)
  row.Profit:SetJustifyH("LEFT")
  row.Profit:SetTextColor(0.3, 1, 0.3)

  local btnX = profitX + COL_PROFIT_W + COL_GAP
  row.SearchBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.SearchBtn:SetSize(COL_BTN_W, 20)
  row.SearchBtn:SetPoint("LEFT", btnX, 0)
  row.SearchBtn:SetText("Search")
  row.SearchBtn:GetFontString():SetTextColor(1, 0.82, 0)

  row.Item:SetScript("OnEnter", function(self)
    if row.flip and row.flip.itemLink then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(row.flip.itemLink)
      GameTooltip:Show()
    end
  end)
  row.Item:SetScript("OnLeave", function()
    GameTooltip_Hide()
  end)
  row.Item:SetScript("OnClick", function(self, mouseButton)
    if IsModifiedClick("CHATLINK") and row.flip and row.flip.itemLink then
      ChatEdit_InsertLink(row.flip.itemLink)
    end
  end)

  row.SearchBtn:SetScript("OnClick", function()
    if row.flip then
      FF:OpenItemDetails(row.flip)
    end
  end)

  return row
end

local function CreatePanel()
  if FF.panel then
    return FF.panel
  end

  if not AuctionHouseFrame then
    return nil
  end

  local panel = CreateFrame("Frame", "FlipFinderResultsPanel", UIParent, "BackdropTemplate")
  panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
  panel:SetPoint("CENTER")
  panel:SetFrameStrata("FULLSCREEN_DIALOG")
  panel:SetFrameLevel(1000)
  panel:EnableMouse(true)
  panel:SetMovable(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:Hide()

  applyTooltipStyle(panel)

  local PAD = 12
  local GAP = 10
  local ROW_H = 24
  local SCROLLBAR_W = 16

  local function NewSeparator()
    local line = panel:CreateTexture(nil, "OVERLAY")
    line:SetHeight(1)
    line:SetColorTexture(0.8, 0.8, 0.8, 0.2)
    return line
  end

  local HEADING_H = 16
  local HEADING_GAP = 8
  local LABEL_H = 14
  local LABEL_GAP = 2
  local INPUT_INSET = 5
  local FIELD_GAP = 20
  local FILTER_H = HEADING_H + HEADING_GAP + LABEL_H + LABEL_GAP + ROW_H

  -- Section 1: Title
  panel.Title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.Title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -PAD)
  panel.Title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -PAD)
  panel.Title:SetHeight(ROW_H)
  panel.Title:SetJustifyH("LEFT")
  panel.Title:SetJustifyV("MIDDLE")
  panel.Title:SetText("Potential Flips")
  panel.Title:SetTextColor(1, 1, 1, 1)

  -- Section 2: Separator below title
  local sepAfterTitle = NewSeparator()
  sepAfterTitle:SetPoint("TOPLEFT", panel.Title, "BOTTOMLEFT", 0, -GAP)
  sepAfterTitle:SetPoint("TOPRIGHT", panel.Title, "BOTTOMRIGHT", 0, -GAP)

  -- Section 3: Filter section (heading + 3 labeled inputs + Save)
  panel.FilterRow = CreateFrame("Frame", nil, panel)
  panel.FilterRow:SetHeight(FILTER_H)
  panel.FilterRow:SetPoint("LEFT", panel, "LEFT", PAD, 0)
  panel.FilterRow:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
  panel.FilterRow:SetPoint("TOP", sepAfterTitle, "BOTTOM", 0, -GAP)

  panel.FilterHeading = panel.FilterRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.FilterHeading:SetPoint("TOPLEFT", panel.FilterRow, "TOPLEFT", 0, 0)
  panel.FilterHeading:SetJustifyH("LEFT")
  panel.FilterHeading:SetText("Table Filter")
  panel.FilterHeading:SetTextColor(1, 1, 1, 1)

  local FILTER_LABEL_START_Y = -HEADING_H - HEADING_GAP

  panel.MinQuantityLabel = panel.FilterRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.MinQuantityLabel:SetPoint("TOPLEFT", panel.FilterRow, "TOPLEFT", INPUT_INSET, FILTER_LABEL_START_Y)
  panel.MinQuantityLabel:SetJustifyH("LEFT")
  panel.MinQuantityLabel:SetText("Min. Total Qty")
  panel.MinQuantityLabel:SetTextColor(0.7, 0.7, 0.7, 1)

  panel.MinQuantityEditBox = CreateFrame("EditBox", nil, panel.FilterRow, "InputBoxTemplate")
  panel.MinQuantityEditBox:SetSize(70, ROW_H)
  panel.MinQuantityEditBox:SetPoint("TOPLEFT", panel.MinQuantityLabel, "BOTTOMLEFT", 0, -LABEL_GAP)
  panel.MinQuantityEditBox:SetAutoFocus(false)
  panel.MinQuantityEditBox:SetNumeric(true)
  panel.MinQuantityEditBox:SetMaxLetters(6)
  panel.MinQuantityEditBox:SetText("1")
  panel.MinQuantityEditBox:SetScript("OnEnterPressed", function()
    panel.MinQuantityEditBox:ClearFocus()
    FF:RebuildFlips()
  end)
  panel.MinQuantityEditBox:SetScript("OnEscapePressed", function()
    panel.MinQuantityEditBox:ClearFocus()
  end)

  panel.MinOrderQtyLabel = panel.FilterRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.MinOrderQtyLabel:SetPoint("TOPLEFT", panel.FilterRow, "TOPLEFT", INPUT_INSET + 70 + FIELD_GAP, FILTER_LABEL_START_Y)
  panel.MinOrderQtyLabel:SetJustifyH("LEFT")
  panel.MinOrderQtyLabel:SetText("Min. Order Qty")
  panel.MinOrderQtyLabel:SetTextColor(0.7, 0.7, 0.7, 1)

  panel.MinOrderQtyEditBox = CreateFrame("EditBox", nil, panel.FilterRow, "InputBoxTemplate")
  panel.MinOrderQtyEditBox:SetSize(70, ROW_H)
  panel.MinOrderQtyEditBox:SetPoint("TOPLEFT", panel.MinOrderQtyLabel, "BOTTOMLEFT", 0, -LABEL_GAP)
  panel.MinOrderQtyEditBox:SetAutoFocus(false)
  panel.MinOrderQtyEditBox:SetNumeric(true)
  panel.MinOrderQtyEditBox:SetMaxLetters(6)
  panel.MinOrderQtyEditBox:SetText("1")
  panel.MinOrderQtyEditBox:SetScript("OnEnterPressed", function()
    panel.MinOrderQtyEditBox:ClearFocus()
    FF:RebuildFlips()
  end)
  panel.MinOrderQtyEditBox:SetScript("OnEscapePressed", function()
    panel.MinOrderQtyEditBox:ClearFocus()
  end)

  panel.MaxInvestLabel = panel.FilterRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.MaxInvestLabel:SetPoint("TOPLEFT", panel.FilterRow, "TOPLEFT", INPUT_INSET + 70 + FIELD_GAP + 70 + FIELD_GAP, FILTER_LABEL_START_Y)
  panel.MaxInvestLabel:SetJustifyH("LEFT")
  panel.MaxInvestLabel:SetText("Max. Invest")
  panel.MaxInvestLabel:SetTextColor(0.7, 0.7, 0.7, 1)

  panel.MaxInvestEditBox = CreateFrame("EditBox", nil, panel.FilterRow, "InputBoxTemplate")
  panel.MaxInvestEditBox:SetSize(100, ROW_H)
  panel.MaxInvestEditBox:SetPoint("TOPLEFT", panel.MaxInvestLabel, "BOTTOMLEFT", 0, -LABEL_GAP)
  panel.MaxInvestEditBox:SetAutoFocus(false)
  panel.MaxInvestEditBox:SetNumeric(true)
  panel.MaxInvestEditBox:SetMaxLetters(10)
  panel.MaxInvestEditBox:SetText("200000")
  panel.MaxInvestEditBox:SetScript("OnEnterPressed", function()
    panel.MaxInvestEditBox:ClearFocus()
    FF:RebuildFlips()
  end)
  panel.MaxInvestEditBox:SetScript("OnEscapePressed", function()
    panel.MaxInvestEditBox:ClearFocus()
  end)

  panel.MinMarginLabel = panel.FilterRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.MinMarginLabel:SetPoint("TOPLEFT", panel.FilterRow, "TOPLEFT", INPUT_INSET + 70 + FIELD_GAP + 70 + FIELD_GAP + 100 + FIELD_GAP, FILTER_LABEL_START_Y)
  panel.MinMarginLabel:SetJustifyH("LEFT")
  panel.MinMarginLabel:SetText("Min. Price Margin (in %)")
  panel.MinMarginLabel:SetTextColor(0.7, 0.7, 0.7, 1)

  panel.MinMarginEditBox = CreateFrame("EditBox", nil, panel.FilterRow, "InputBoxTemplate")
  panel.MinMarginEditBox:SetSize(70, ROW_H)
  panel.MinMarginEditBox:SetPoint("TOPLEFT", panel.MinMarginLabel, "BOTTOMLEFT", 0, -LABEL_GAP)
  panel.MinMarginEditBox:SetAutoFocus(false)
  panel.MinMarginEditBox:SetNumeric(true)
  panel.MinMarginEditBox:SetMaxLetters(3)
  panel.MinMarginEditBox:SetText(tostring(math.floor((PRICE_JUMP_RATIO - 1) * 100 + 0.5)))
  panel.MinMarginEditBox:SetScript("OnEnterPressed", function()
    panel.MinMarginEditBox:ClearFocus()
    FF:RebuildFlips()
  end)
  panel.MinMarginEditBox:SetScript("OnEscapePressed", function()
    panel.MinMarginEditBox:ClearFocus()
  end)

  panel.SaveFilterBtn = CreateFrame("Button", nil, panel.FilterRow, "UIPanelButtonTemplate")
  panel.SaveFilterBtn:SetSize(80, ROW_H)
  panel.SaveFilterBtn:SetPoint("BOTTOMRIGHT", panel.FilterRow, "BOTTOMRIGHT", 0, 0)
  panel.SaveFilterBtn:SetText("Save")
  panel.SaveFilterBtn:GetFontString():SetTextColor(1, 0.82, 0)
  panel.SaveFilterBtn:SetScript("OnClick", function() FF:RebuildFlips() end)

  -- Section 4: Separator below filter, above table
  local sepAfterFilter = NewSeparator()
  sepAfterFilter:SetPoint("TOPLEFT", panel.FilterRow, "BOTTOMLEFT", 0, -GAP)
  sepAfterFilter:SetPoint("TOPRIGHT", panel.FilterRow, "BOTTOMRIGHT", 0, -GAP)

  -- Section 5.1: Column headers
  panel.HeaderRow = CreateFrame("Frame", nil, panel)
  panel.HeaderRow:SetHeight(ROW_H)
  panel.HeaderRow:SetPoint("LEFT", panel, "LEFT", PAD, 0)
  panel.HeaderRow:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
  panel.HeaderRow:SetPoint("TOP", sepAfterFilter, "BOTTOM", 0, -GAP)

  panel.HeaderItem = panel.HeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.HeaderItem:SetPoint("LEFT", panel.HeaderRow, "LEFT", 0, 0)
  panel.HeaderItem:SetWidth(COL_ITEM_W)
  panel.HeaderItem:SetJustifyH("LEFT")
  panel.HeaderItem:SetText("Item Name")
  panel.HeaderItem:SetTextColor(0.7, 0.7, 0.7, 1)

  panel.HeaderQty = panel.HeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.HeaderQty:SetPoint("LEFT", panel.HeaderRow, "LEFT", COL_ITEM_W + COL_GAP, 0)
  panel.HeaderQty:SetWidth(COL_QTY_W)
  panel.HeaderQty:SetJustifyH("LEFT")
  panel.HeaderQty:SetText("Quantity")
  panel.HeaderQty:SetTextColor(0.7, 0.7, 0.7, 1)

  panel.HeaderCost = panel.HeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.HeaderCost:SetPoint("LEFT", panel.HeaderRow, "LEFT", COL_ITEM_W + COL_GAP + COL_QTY_W + COL_GAP, 0)
  panel.HeaderCost:SetWidth(COL_COST_W)
  panel.HeaderCost:SetJustifyH("LEFT")
  panel.HeaderCost:SetText("Invest")
  panel.HeaderCost:SetTextColor(0.7, 0.7, 0.7, 1)

  panel.HeaderOrder = panel.HeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.HeaderOrder:SetPoint("LEFT", panel.HeaderRow, "LEFT", COL_ITEM_W + COL_GAP + COL_QTY_W + COL_GAP + COL_COST_W + COL_GAP, 0)
  panel.HeaderOrder:SetWidth(COL_ORDER_W)
  panel.HeaderOrder:SetJustifyH("LEFT")
  panel.HeaderOrder:SetText("Order Qty")
  panel.HeaderOrder:SetTextColor(0.7, 0.7, 0.7, 1)

  panel.HeaderProfit = panel.HeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.HeaderProfit:SetPoint("LEFT", panel.HeaderRow, "LEFT", COL_ITEM_W + COL_GAP + COL_QTY_W + COL_GAP + COL_COST_W + COL_GAP + COL_ORDER_W + COL_GAP, 0)
  panel.HeaderProfit:SetWidth(COL_PROFIT_W)
  panel.HeaderProfit:SetJustifyH("LEFT")
  panel.HeaderProfit:SetText("Profit")
  panel.HeaderProfit:SetTextColor(0.7, 0.7, 0.7, 1)

  -- Section 5.2: Status message (right-aligned, 14pt) - defined first
  panel.StatusText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  do
    local fontFile, _, fontFlags = panel.StatusText:GetFont()
    panel.StatusText:SetFont(fontFile, 14, fontFlags)
  end
  panel.StatusText:SetPoint("LEFT", panel, "LEFT", PAD + 4, 0)
  panel.StatusText:SetPoint("RIGHT", panel, "RIGHT", -(PAD + 4), 0)
  panel.StatusText:SetPoint("BOTTOM", panel, "BOTTOM", 0, PAD + 4)
  panel.StatusText:SetHeight(ROW_H)
  panel.StatusText:SetJustifyH("LEFT")
  panel.StatusText:SetJustifyV("MIDDLE")
  panel.StatusText:SetText("Run a Shopping List search in Auctionator, then click Scan for Flips to scan for potential flips.")
  panel.StatusText:SetTextColor(1, 1, 1, 1)

  -- Section 5.3: Separator above status
  local sepStatus = NewSeparator()
  sepStatus:SetPoint("LEFT", panel, "LEFT", PAD, 0)
  sepStatus:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
  sepStatus:SetPoint("BOTTOM", panel.StatusText, "TOP", 0, GAP)

  -- Section 6: Actions row (Cancel + Scan for Flips)
  panel.ActionsRow = CreateFrame("Frame", nil, panel)
  panel.ActionsRow:SetHeight(ROW_H)
  panel.ActionsRow:SetPoint("LEFT", panel, "LEFT", PAD, 0)
  panel.ActionsRow:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
  panel.ActionsRow:SetPoint("BOTTOM", sepStatus, "TOP", 0, GAP)

  panel.CancelBtn = CreateFrame("Button", nil, panel.ActionsRow, "UIPanelButtonTemplate")
  panel.CancelBtn:SetSize(80, ROW_H)
  panel.CancelBtn:SetPoint("LEFT", panel.ActionsRow, "LEFT", 0, 0)
  panel.CancelBtn:SetText("Cancel")
  panel.CancelBtn:GetFontString():SetTextColor(1, 0.82, 0)
  panel.CancelBtn:SetScript("OnClick", function() panel:Hide() end)

  panel.FlipScanBtn = CreateFrame("Button", nil, panel.ActionsRow, "UIPanelButtonTemplate")
  panel.FlipScanBtn:SetSize(120, ROW_H)
  panel.FlipScanBtn:SetPoint("RIGHT", panel.ActionsRow, "RIGHT", 0, 0)
  panel.FlipScanBtn:SetText("Scan for Flips")
  panel.FlipScanBtn:GetFontString():SetTextColor(1, 0.82, 0)
  panel.FlipScanBtn:SetScript("OnClick", function() FF:StartScan() end)

  -- Section 7: Separator below table, above actions
  local sepBeforeActions = NewSeparator()
  sepBeforeActions:SetPoint("LEFT", panel, "LEFT", PAD, 0)
  sepBeforeActions:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
  sepBeforeActions:SetPoint("BOTTOM", panel.ActionsRow, "TOP", 0, GAP)

  -- Section 8: Scroll area
  panel.Scroll = CreateFrame("ScrollFrame", "FlipFinderResultsScroll", panel)
  panel.Scroll:SetPoint("TOPLEFT", panel.HeaderRow, "BOTTOMLEFT", 0, -GAP)
  panel.Scroll:SetPoint("BOTTOMRIGHT", sepBeforeActions, "BOTTOMRIGHT", -(SCROLLBAR_W + 4), GAP)
  panel.Scroll:EnableMouseWheel(true)
  panel.Scroll:SetScript("OnMouseWheel", function(self, delta)
    local scrollBar = panel.ScrollScrollBar
    local step = ROW_HEIGHT * 2
    local newValue = scrollBar:GetValue() - (delta * step)
    local minVal, maxVal = scrollBar:GetMinMaxValues()
    scrollBar:SetValue(math.max(minVal, math.min(maxVal, newValue)))
  end)

  panel.ScrollBackground = panel.Scroll:CreateTexture(nil, "BACKGROUND")
  panel.ScrollBackground:SetAllPoints()
  panel.ScrollBackground:SetColorTexture(0.05, 0.05, 0.05, 0.5)

  panel.ScrollScrollBar = CreateFrame("Slider", "FlipFinderScrollBar", panel.Scroll, "UIPanelScrollBarTemplate")
  panel.ScrollScrollBar:SetPoint("TOPRIGHT", panel.Scroll, "TOPRIGHT", -4, -8)
  panel.ScrollScrollBar:SetPoint("BOTTOMRIGHT", panel.Scroll, "BOTTOMRIGHT", -4, 8)
  panel.ScrollScrollBar:SetMinMaxValues(0, 0)
  panel.ScrollScrollBar:SetValueStep(1)
  panel.ScrollScrollBar:SetValue(0)
  panel.ScrollScrollBar:Hide()
  panel.ScrollScrollBar:SetScript("OnValueChanged", function(self, value)
    panel.Scroll:SetVerticalScroll(value)
  end)

  panel.Content = CreateFrame("Frame", nil, panel.Scroll)
  panel.Content:SetSize(PANEL_WIDTH - PAD * 2 - SCROLLBAR_W, 1)
  panel.Scroll:SetScrollChild(panel.Content)

  panel.EmptyMessage = panel.Scroll:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.EmptyMessage:SetPoint("CENTER", panel.Scroll, "CENTER", 0, 0)
  panel.EmptyMessage:SetText("No potential flips found.")
  panel.EmptyMessage:SetTextColor(0.5, 0.5, 0.5, 1)

  -- Close button
  local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  closeBtn:SetSize(24, 24)
  closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 4, 4)
  closeBtn:SetFrameLevel(panel:GetFrameLevel() + 10)
  closeBtn:SetScript("OnClick", function() panel:Hide() end)

  panel.rows = {}

  function panel:SetStatus(text)
    self.StatusText:SetText(text or "")
  end

  function panel:Render()
    local flips = FF.flips

    table.sort(flips, function(a, b) return a.totalCost < b.totalCost end)

    if #flips == 0 then
      self.EmptyMessage:Show()
    else
      self.EmptyMessage:Hide()
    end

    for i, flip in ipairs(flips) do
      local row = self.rows[i]
      if not row then
        row = CreateRow(self.Content, i)
        self.rows[i] = row
      end

      row.flip = flip
      local itemText = flip.itemLink or flip.itemName or "?"
      itemText = itemText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      itemText = itemText:gsub("|T[^|]+|t", ""):gsub("|H[^|]+|h", ""):gsub("|h", "")
      itemText = strtrim(itemText)
      row.Item.Text:SetText(itemText)
      row.Quantity:SetText(string.format("%.0f", flip.displayQuantity))
      row.TotalCost:SetText(FormatGold(flip.totalCost))
      row.OrderQty:SetText(string.format("%.0f", flip.totalQuantity))
      row.Profit:SetText(FormatGold(flip.margin))
      row:Show()
    end

    for i = #flips + 1, #self.rows do
      self.rows[i]:Hide()
      self.rows[i].flip = nil
    end

    local neededHeight = #flips * ROW_HEIGHT
    self.Content:SetHeight(math.max(neededHeight, 1))

    local scrollRange = math.max(0, neededHeight - self.Scroll:GetHeight())
    self.ScrollScrollBar:SetMinMaxValues(0, scrollRange)

    if scrollRange > 0 then
      self.ScrollScrollBar:Show()
    else
      self.ScrollScrollBar:Hide()
    end
  end

  FF.panel = panel
  return panel
end

local function TogglePanel()
  local panel = FF.panel or CreatePanel()
  if not panel then
    return
  end

  if panel:IsShown() then
    panel:Hide()
  else
    panel:Show()
    panel:Render()
  end
end

local function CreateScanButton()
  if FF.scanButton then
    return true
  end

  local anchor = AuctionatorShoppingFrame and AuctionatorShoppingFrame.ExportCSV
  if not anchor then
    return false
  end

  local button = CreateFrame(
    "Button", "FlipFinderScanButton",
    AuctionatorShoppingFrame, "UIPanelButtonTemplate"
  )
  button:SetSize(150, 22)
  button:SetText("FlipFinder")
  button:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
  button:SetFrameStrata(anchor:GetFrameStrata())
  button:SetFrameLevel(anchor:GetFrameLevel() + 1)
  button:SetScript("OnClick", TogglePanel)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Toggle FlipFinder panel")
    GameTooltip:AddLine("Lists items whose lowest auctions span a price gap above the configured margin.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", GameTooltip_Hide)
  button:Show()

  FF.scanButton = button
  return true
end

local function EnsureScanButton(attempt)
  attempt = attempt or 1
  if CreateScanButton() or attempt > 20 then
    return
  end

  C_Timer.After(0.5, function()
    EnsureScanButton(attempt + 1)
  end)
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:RegisterEvent("AUCTION_HOUSE_SHOW")
bootstrap:RegisterEvent("AUCTION_HOUSE_CLOSED")
bootstrap:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    RegisterEventBus()

  elseif event == "AUCTION_HOUSE_SHOW" then
    RegisterEventBus()
    EnsureScanButton()

  elseif event == "AUCTION_HOUSE_CLOSED" then
    FF:AbortScan()
    if FF.panel then
      FF.panel:Hide()
    end
  end
end)
