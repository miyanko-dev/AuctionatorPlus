local _, AP = ...

AP.Panel = {}

local C = AP.Constants
local COL = C.Columns

local CONTENT_PAD = 10
local CONTENT_PAD_TOP = 30
local SECTION_GAP = 22
local SECTION_INNER_PAD = 12
local SECTION_LABEL_LIFT = 7
local ACTION_BUTTON_W = 180
local ACTION_BUTTON_H = 24
local ACTION_AREA_H = ACTION_BUTTON_H + 12

local SECTION_BACKDROP = {
  bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile     = true,
  tileSize = 16,
  edgeSize = 16,
  insets   = { left = 3, right = 3, top = 5, bottom = 3 },
}

local function BuildSection(parent, labelText)
  local section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  section:SetBackdrop(SECTION_BACKDROP)
  section:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
  section:SetBackdropBorderColor(0.4, 0.4, 0.4)

  if labelText and labelText ~= "" then
    local label = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", section, "TOPLEFT", 12, SECTION_LABEL_LIFT)
    label:SetText(labelText)
    section.label = label
  end

  local body = CreateFrame("Frame", nil, section)
  body:SetPoint("TOPLEFT", section, "TOPLEFT", SECTION_INNER_PAD, -SECTION_INNER_PAD)
  body:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", -SECTION_INNER_PAD, SECTION_INNER_PAD)
  section.body = body

  return section
end

local function MakeCellField(row, width, x)
  local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("LEFT", x, 0)
  fs:SetWidth(width)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  return fs
end

local function InitRowWidgets(row)
  if row.initialized then return end
  row.initialized = true
  row:SetHeight(C.RowHeight)

  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(row)
  highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  highlight:SetBlendMode("ADD")

  row.ItemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.ItemText:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.ItemText:SetWidth(COL.Item - 4)
  row.ItemText:SetJustifyH("LEFT")
  row.ItemText:SetWordWrap(false)

  local x = COL.Item + COL.Gap
  row.RelQty      = MakeCellField(row, COL.RelQty,      x); x = x + COL.RelQty      + COL.Gap
  row.Underpriced = MakeCellField(row, COL.Underpriced, x); x = x + COL.Underpriced + COL.Gap
  row.Vol         = MakeCellField(row, COL.Vol,         x); x = x + COL.Vol         + COL.Gap
  row.Sellers     = MakeCellField(row, COL.Sellers,     x); x = x + COL.Sellers     + COL.Gap
  row.TotalCost   = MakeCellField(row, COL.Cost,        x); x = x + COL.Cost        + COL.Gap
  row.Profit      = MakeCellField(row, COL.Profit,      x); x = x + COL.Profit      + COL.Gap
  row.ROI         = MakeCellField(row, COL.ROI,         x)
  row.ROI:SetTextColor(0.3, 1, 0.3)

  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnEnter", function(self)
    if self.flip and self.flip.itemLink then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(self.flip.itemLink)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", GameTooltip_Hide)
  row:SetScript("OnClick", function(self, button)
    if not self.flip then return end
    if button == "RightButton" and self.flip.itemLink then
      if IsModifiedClick("CHATLINK") then
        ChatEdit_InsertLink(self.flip.itemLink)
      end
    else
      AP.Arbitrage.OpenFlipDetails(self.flip)
    end
  end)
end

local function UpdateRow(row, flip)
  row.flip = flip
  row.ItemText:SetText(AP.Format.CleanItemText(flip.itemLink or flip.itemName or "?"))
  row.RelQty:SetText(string.format("%.0f%%", flip.relativeQuantity or 0))
  row.Underpriced:SetText(flip.underpriced and string.format("%+d%%", flip.underpriced) or "-")
  row.Vol:SetText(flip.volatilityBucket or "-")
  row.Sellers:SetText(flip.sellers and tostring(flip.sellers) or "-")
  row.TotalCost:SetText(AP.Format.Money(flip.totalCost))
  row.Profit:SetText(AP.Format.Money(flip.margin))
  row.ROI:SetText(string.format("%.0f%%", (flip.roi or 0) * 100))
end

function AP.Panel.Create()
  if AP.panel then return AP.panel end
  if not AuctionFrame then return nil end

  local panel = CreateFrame("Frame", "AuctionatorPlusArbitragePanel", UIParent, "ButtonFrameTemplate")
  ButtonFrameTemplate_HidePortrait(panel)
  panel:SetTitle("Arbitrage")

  -- The template reserves a streaky "attic" band between the title bar (21px)
  -- and the inset; this panel has no attic content, so reclaim it.
  panel.TopTileStreaks:Hide()
  panel.Inset:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -21)
  panel:SetSize(C.PanelWidth, C.PanelHeight)
  panel:SetPoint("CENTER")
  panel:SetFrameStrata("FULLSCREEN_DIALOG")
  panel:SetFrameLevel(1000)
  panel:EnableMouse(true)
  panel:SetMovable(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:Hide()
  panel.CloseButton:SetScript("OnClick", function() panel:Hide() end)

  -- Section labels render above their section's top border, so the content
  -- area leaves enough room for the first label plus a gap to the inset edge.
  local content = CreateFrame("Frame", nil, panel)
  content:SetPoint("TOPLEFT", panel.Inset, "TOPLEFT", CONTENT_PAD, -CONTENT_PAD_TOP)
  content:SetPoint("BOTTOMRIGHT", panel.Inset, "BOTTOMRIGHT", -CONTENT_PAD, CONTENT_PAD)

  local ROW_H = 24
  local LABEL_H = 14
  local LABEL_GAP = 2
  local INPUT_INSET = 5
  local FIELD_GAP = 18
  local MINI_HELPER_H = 28
  local MINI_HELPER_GAP = 4
  local SECTION_BODY_INSET = 4

  local FILTER_DEFS = {
    { key = "MaxQtyPct", label = "Purchase Share (%)",
      width = 150, maxLetters = 3,  default = "",
      helper = "Skip flips that buy out more than this share of listed stock." },
    { key = "MaxInvest", label = "Investment (g)",
      width = 150, maxLetters = 10, default = "",
      helper = "Skip flips costing more than this in gold." },
    { key = "MinProfit", label = "Profit (g)",
      width = 150, maxLetters = 10, default = "",
      helper = "Skip flips whose post-cut, post-deposit profit is below this in gold." },
    { key = "MinROI", label = "ROI (%)",
      width = 120, maxLetters = 3,  default = tostring(C.DefaultMinROIPercent),
      helper = "Skip flips below this return on invested gold." },
  }

  local FILTERS_BODY_H = LABEL_H + LABEL_GAP + ROW_H + MINI_HELPER_GAP + MINI_HELPER_H
  local FILTERS_SECTION_H = FILTERS_BODY_H + 2 * SECTION_INNER_PAD

  panel.FiltersSection = BuildSection(content, "Filters")
  panel.FiltersSection:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  panel.FiltersSection:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
  panel.FiltersSection:SetHeight(FILTERS_SECTION_H)

  local function CreateFilterField(parent, colX, def)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", colX, 0)
    label:SetWidth(def.width)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(def.label)
    label:SetTextColor(0.85, 0.85, 0.85, 1)

    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(def.width, ROW_H)
    edit:SetPoint("TOPLEFT", label, "BOTTOMLEFT", INPUT_INSET, -LABEL_GAP)
    edit:SetAutoFocus(false)
    edit:SetNumeric(true)
    edit:SetMaxLetters(def.maxLetters)
    edit:SetText(def.default or "")
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnTextChanged", function()
      if AP.hasScanned then AP.Arbitrage.RebuildAll() end
    end)

    local mini = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mini:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -INPUT_INSET, -MINI_HELPER_GAP)
    mini:SetWidth(def.width)
    mini:SetHeight(MINI_HELPER_H)
    mini:SetJustifyH("LEFT")
    mini:SetJustifyV("TOP")
    mini:SetWordWrap(true)
    mini:SetText(def.helper)
    mini:SetTextColor(0.55, 0.55, 0.55, 1)

    return edit
  end

  local filtersBody = panel.FiltersSection.body
  local colCursor = SECTION_BODY_INSET
  panel.inputs = {}
  for _, def in ipairs(FILTER_DEFS) do
    panel.inputs[def.key] = CreateFilterField(filtersBody, colCursor, def)
    colCursor = colCursor + def.width + FIELD_GAP
  end

  panel.ActionButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  panel.ActionButton:SetSize(ACTION_BUTTON_W, ACTION_BUTTON_H)
  panel.ActionButton:SetPoint("BOTTOM", content, "BOTTOM", 0, 0)
  panel.ActionButton:SetText("Find Potential Flips")
  panel.ActionButton:GetFontString():SetTextColor(1, 0.82, 0)
  panel.ActionButton:SetScript("OnClick", function()
    if AP.Arbitrage.scanning then
      AP.Arbitrage.Abort()
    else
      AP.Arbitrage.Start()
    end
  end)

  panel.TableSection = BuildSection(content, "Potential Flips")
  panel.TableSection:SetPoint("TOPLEFT", panel.FiltersSection, "BOTTOMLEFT", 0, -SECTION_GAP)
  panel.TableSection:SetPoint("TOPRIGHT", panel.FiltersSection, "BOTTOMRIGHT", 0, -SECTION_GAP)
  panel.TableSection:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, ACTION_AREA_H)
  panel.TableSection:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, ACTION_AREA_H)

  local tableBody = panel.TableSection.body
  local SCROLLBAR_W = 16

  panel.HeaderRow = CreateFrame("Frame", nil, tableBody)
  panel.HeaderRow:SetHeight(ROW_H)
  panel.HeaderRow:SetPoint("TOPLEFT", tableBody, "TOPLEFT", SECTION_BODY_INSET, 0)
  panel.HeaderRow:SetPoint("TOPRIGHT", tableBody, "TOPRIGHT", -SECTION_BODY_INSET, 0)

  local HEADER_COLS = {
    { key = "itemName",         label = "Item Name",      width = COL.Item,        defaultDir = "asc"  },
    { key = "relativeQuantity", label = "Purchase Share", width = COL.RelQty,      defaultDir = "asc"  },
    { key = "underpriced",      label = "Underpriced",    width = COL.Underpriced, defaultDir = "asc"  },
    { key = "volatility",       label = "Vol",            width = COL.Vol,         defaultDir = "asc"  },
    { key = "sellers",          label = "Sellers",        width = COL.Sellers,     defaultDir = "asc"  },
    { key = "totalCost",        label = "Investment",     width = COL.Cost,        defaultDir = "asc"  },
    { key = "margin",           label = "Profit",         width = COL.Profit,      defaultDir = "desc" },
    { key = "roi",              label = "ROI",            width = COL.ROI,         defaultDir = "desc" },
  }

  panel.HeaderButtons = {}

  local function CreateSortHeader(def, x)
    local btn = CreateFrame("Button", nil, panel.HeaderRow)
    btn:SetPoint("LEFT", panel.HeaderRow, "LEFT", x, 0)
    btn:SetSize(def.width, ROW_H)
    btn:RegisterForClicks("LeftButtonUp")

    btn.Text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.Text:SetPoint("LEFT", btn, "LEFT", 0, 0)
    btn.Text:SetJustifyH("LEFT")
    btn.Text:SetText(def.label)

    btn.Arrow = btn:CreateTexture(nil, "OVERLAY")
    btn.Arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    btn.Arrow:SetSize(9, 8)
    btn.Arrow:SetPoint("LEFT", btn.Text, "RIGHT", 3, 0)
    btn.Arrow:Hide()

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(btn)
    highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.5)

    btn:SetScript("OnClick", function()
      if AP.sortProperty == def.key then
        AP.sortDirection = (AP.sortDirection == "asc") and "desc" or "asc"
      else
        AP.sortProperty = def.key
        AP.sortDirection = def.defaultDir
      end
      panel:RefreshSortIndicators()
      panel:Render()
    end)

    btn.sortKey = def.key
    return btn
  end

  local headerX = 0
  for _, def in ipairs(HEADER_COLS) do
    table.insert(panel.HeaderButtons, CreateSortHeader(def, headerX))
    headerX = headerX + def.width + COL.Gap
  end

  panel.Scroll = CreateFrame("ScrollFrame", nil, tableBody)
  panel.Scroll:SetPoint("TOPLEFT", panel.HeaderRow, "BOTTOMLEFT", 0, -6)
  panel.Scroll:SetPoint("BOTTOMRIGHT", tableBody, "BOTTOMRIGHT", -SECTION_BODY_INSET - SCROLLBAR_W, 0)
  panel.Scroll:EnableMouseWheel(true)

  panel.Content = CreateFrame("Frame", nil, panel.Scroll)
  panel.Content:SetSize(1, 1)
  panel.Scroll:SetScrollChild(panel.Content)

  panel.ScrollBar = CreateFrame("EventFrame", nil, tableBody, "MinimalScrollBar")
  panel.ScrollBar:SetPoint("TOPLEFT", panel.Scroll, "TOPRIGHT", 4, -4)
  panel.ScrollBar:SetPoint("BOTTOMLEFT", panel.Scroll, "BOTTOMRIGHT", 4, 7)
  panel.ScrollBar:SetHideIfUnscrollable(true)
  panel.ScrollBar:Init(1, 0.25)

  panel.ScrollBar:RegisterCallback("OnScroll", function(_, scrollPercentage)
    local range = math.max(0, panel.Content:GetHeight() - panel.Scroll:GetHeight())
    panel.Scroll:SetVerticalScroll(range * scrollPercentage)
  end, panel.Scroll)

  panel.Scroll:SetScript("OnMouseWheel", function(_, delta)
    if not panel.ScrollBar:HasScrollableExtent() then return end
    local pct = panel.ScrollBar:GetScrollPercentage() - delta * 0.1
    panel.ScrollBar:SetScrollPercentage(math.max(0, math.min(1, pct)))
  end)

  panel.rows = {}

  panel.EmptyMessage = tableBody:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.EmptyMessage:SetPoint("TOPLEFT", panel.Scroll, "TOPLEFT", 0, 0)
  panel.EmptyMessage:SetPoint("BOTTOMRIGHT", panel.Scroll, "BOTTOMRIGHT", 0, 0)
  panel.EmptyMessage:SetJustifyH("CENTER")
  panel.EmptyMessage:SetJustifyV("MIDDLE")
  panel.EmptyMessage:SetWordWrap(true)
  panel.EmptyMessage:SetTextColor(0.55, 0.55, 0.55, 1)
  panel.EmptyMessage:SetText("Run a shopping list search in Auctionator, then click Find Potential Flips.")

  function panel:SetScanningUI(active)
    if active then
      self.ActionButton:SetText("Cancel Scan")
    else
      self.ActionButton:SetText("Find Potential Flips")
    end
  end

  function panel:RefreshSortIndicators()
    for _, btn in ipairs(self.HeaderButtons) do
      if AP.sortProperty == btn.sortKey then
        btn.Arrow:Show()
        if AP.sortDirection == "asc" then
          btn.Arrow:SetTexCoord(0, 0.5625, 0, 1)
        else
          btn.Arrow:SetTexCoord(0.5625, 1, 0, 1)
        end
        btn.Text:SetTextColor(1, 0.82, 0, 1)
      else
        btn.Arrow:Hide()
        btn.Text:SetTextColor(0.85, 0.85, 0.85, 1)
      end
    end
  end

  function panel:Render()
    self:RefreshSortIndicators()
    AP.Arbitrage.SortFlips(AP.flips)

    if #AP.flips > 0 then
      self.EmptyMessage:Hide()
    else
      if AP.hasScanned then
        self.EmptyMessage:SetText("No flips found. Try adjusting your filters or broadening your shopping list search.")
      else
        self.EmptyMessage:SetText("Run a shopping list search in Auctionator, then click Find Potential Flips.")
      end
      self.EmptyMessage:Show()
    end

    -- The scroll child cannot be anchored to the scroll frame's width, so it
    -- follows the laid-out width here (skipped before the first layout pass).
    local scrollWidth = self.Scroll:GetWidth()
    if scrollWidth and scrollWidth > 0 then
      self.Content:SetWidth(scrollWidth)
    end

    for i, flip in ipairs(AP.flips) do
      local row = self.rows[i]
      if not row then
        row = CreateFrame("Button", nil, self.Content)
        row:SetHeight(C.RowHeight)
        row:SetPoint("TOPLEFT",  self.Content, "TOPLEFT",  0, -(i - 1) * C.RowHeight)
        row:SetPoint("TOPRIGHT", self.Content, "TOPRIGHT", 0, -(i - 1) * C.RowHeight)
        InitRowWidgets(row)
        self.rows[i] = row
      end
      UpdateRow(row, flip)
      row:Show()
    end

    for i = #AP.flips + 1, #self.rows do
      self.rows[i]:Hide()
      self.rows[i].flip = nil
    end

    local contentHeight = #AP.flips * C.RowHeight
    self.Content:SetHeight(math.max(contentHeight, 1))

    local viewport = self.Scroll:GetHeight()
    local visiblePct = math.min(1, viewport / math.max(contentHeight, 1))
    self.ScrollBar:SetVisibleExtentPercentage(visiblePct)
    local range = math.max(0, contentHeight - viewport)
    self.Scroll:SetVerticalScroll(range * self.ScrollBar:GetScrollPercentage())
  end

  AP.panel = panel
  return panel
end

function AP.Panel.Toggle()
  local panel = AP.panel or AP.Panel.Create()
  if not panel then return end

  if panel:IsShown() then
    panel:Hide()
    return
  end

  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", AuctionFrame, "TOPRIGHT", 10, 0)
  panel:Show()
  panel:Render()
end
