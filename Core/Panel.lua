FF.Panel = {}

local C = FF.Constants
local COL = C.Columns

local PAD_X = 16
local PAD_TOP = 52
local PAD_BOTTOM = 16
local SECTION_GAP = 22
local SECTION_INNER_PAD = 12
local SECTION_LABEL_LIFT = 7
local ACTION_BUTTON_W = 180
local ACTION_BUTTON_H = 24
local ACTION_AREA_H = ACTION_BUTTON_H + 12

local PANEL_BACKDROP = {
  bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile     = true,
  tileSize = 32,
  edgeSize = 32,
  insets   = { left = 8, right = 8, top = 8, bottom = 8 },
}

local SECTION_BACKDROP = {
  bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile     = true,
  tileSize = 16,
  edgeSize = 16,
  insets   = { left = 3, right = 3, top = 5, bottom = 3 },
}

local function applyPanelBackdrop(frame)
  if not frame.SetBackdrop then return end
  frame:SetBackdrop(PANEL_BACKDROP)
end

local function buildTitleHeader(parent, text)
  local HEADER_TEXTURE = "Interface\\DialogFrame\\UI-DialogBox-Header"

  local mid = parent:CreateTexture(nil, "OVERLAY")
  mid:SetTexture(HEADER_TEXTURE)
  mid:SetTexCoord(0.31, 0.67, 0, 0.63)
  mid:SetPoint("TOP", parent, "TOP", 0, 12)
  mid:SetHeight(40)

  local left = parent:CreateTexture(nil, "OVERLAY")
  left:SetTexture(HEADER_TEXTURE)
  left:SetTexCoord(0.21, 0.31, 0, 0.63)
  left:SetPoint("RIGHT", mid, "LEFT")
  left:SetWidth(30)
  left:SetHeight(40)

  local right = parent:CreateTexture(nil, "OVERLAY")
  right:SetTexture(HEADER_TEXTURE)
  right:SetTexCoord(0.67, 0.77, 0, 0.63)
  right:SetPoint("LEFT", mid, "RIGHT")
  right:SetWidth(30)
  right:SetHeight(40)

  local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", mid, "TOP", 0, -14)
  title:SetText(text)

  mid:SetWidth((title:GetStringWidth() or 0) + 10)
end

local function buildSection(parent, labelText)
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

  local relQtyX = COL.Item + COL.Gap
  row.RelQty = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.RelQty:SetPoint("LEFT", relQtyX, 0)
  row.RelQty:SetWidth(COL.RelQty)
  row.RelQty:SetJustifyH("LEFT")

  local depthX = relQtyX + COL.RelQty + COL.Gap
  row.Depth = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.Depth:SetPoint("LEFT", depthX, 0)
  row.Depth:SetWidth(COL.Depth)
  row.Depth:SetJustifyH("LEFT")

  local costX = depthX + COL.Depth + COL.Gap
  row.TotalCost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.TotalCost:SetPoint("LEFT", costX, 0)
  row.TotalCost:SetWidth(COL.Cost)
  row.TotalCost:SetJustifyH("LEFT")

  local roiX = costX + COL.Cost + COL.Gap
  row.ROI = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.ROI:SetPoint("LEFT", roiX, 0)
  row.ROI:SetWidth(COL.ROI)
  row.ROI:SetJustifyH("LEFT")
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
      if FF.Adapter and FF.Adapter.OpenFlipDetails then
        FF.Adapter.OpenFlipDetails(self.flip)
      end
    end
  end)
end

local function UpdateRow(row, flip)
  row.flip = flip
  local text = flip.itemLink or flip.itemName or "?"
  row.ItemText:SetText(FF.Format.CleanItemText(text))
  row.RelQty:SetText(string.format("%.0f%%", flip.relativeQuantity or 0))
  row.Depth:SetText(string.format("%.0f", flip.sellSideDepth or 0))
  row.TotalCost:SetText(FF.Format.Money(flip.totalCost))
  row.ROI:SetText(string.format("%.0f%%", (flip.roi or 0) * 100))
end

local function GetAHFrame()
  if FF.Adapter and FF.Adapter.GetAuctionHouseFrame then
    return FF.Adapter.GetAuctionHouseFrame()
  end
  return nil
end

function FF.Panel.Create()
  if FF.panel then return FF.panel end
  if not GetAHFrame() then return nil end

  local panel = CreateFrame("Frame", "FlipperResultsPanel", UIParent, "BackdropTemplate")
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

  applyPanelBackdrop(panel)
  buildTitleHeader(panel, "Flip Finder")

  local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
  closeBtn:SetScript("OnClick", function() panel:Hide() end)

  local content = CreateFrame("Frame", nil, panel)
  content:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD_X, -PAD_TOP)
  content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD_X, PAD_BOTTOM)

  local ROW_H = 24
  local LABEL_H = 14
  local LABEL_GAP = 2
  local INPUT_INSET = 5
  local FIELD_GAP = 18
  local MINI_HELPER_H = 28
  local MINI_HELPER_GAP = 4
  local SECTION_BODY_INSET = 4

  local FILTER_DEFS = {
    { key = "MaxQtyPct", label = "Max. Relative Order Quantity (%)",
      width = 200, maxLetters = 3,  default = "",
      helper = "Skip flips that buy out more than this share of listed stock." },
    { key = "MinDepth", label = "Min. Listings Depth (n)",
      width = 160, maxLetters = 4,  default = "",
      helper = "Skip flips with fewer listings priced above the gap." },
    { key = "MaxInvest", label = "Max. Investment (g)",
      width = 145, maxLetters = 10, default = "",
      helper = "Skip flips costing more than this in gold." },
    { key = "MinROI", label = "Min. ROI (%)",
      width = 130, maxLetters = 3,  default = tostring(C.DefaultMinROIPercent),
      helper = "Skip flips below this return on invested gold." },
  }

  local FILTERS_BODY_H = LABEL_H + LABEL_GAP + ROW_H + MINI_HELPER_GAP + MINI_HELPER_H
  local FILTERS_SECTION_H = FILTERS_BODY_H + 2 * SECTION_INNER_PAD

  panel.FiltersSection = buildSection(content, "Filters")
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
      if FF.hasScanned then FF.Filters.RebuildAll() end
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

    return label, edit, mini
  end

  local filtersBody = panel.FiltersSection.body
  local colCursor = SECTION_BODY_INSET
  for _, def in ipairs(FILTER_DEFS) do
    local label, edit, mini = CreateFilterField(filtersBody, colCursor, def)
    panel[def.key .. "Label"] = label
    panel[def.key .. "EditBox"] = edit
    panel[def.key .. "MiniHelper"] = mini
    colCursor = colCursor + def.width + FIELD_GAP
  end

  panel.ActionButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  panel.ActionButton:SetSize(ACTION_BUTTON_W, ACTION_BUTTON_H)
  panel.ActionButton:SetPoint("BOTTOM", content, "BOTTOM", 0, 0)
  panel.ActionButton:SetText("Find Potential Flips")
  panel.ActionButton:GetFontString():SetTextColor(1, 0.82, 0)
  panel.ActionButton:SetScript("OnClick", function()
    if FF.Scanner.scanning then
      FF.Scanner.Abort()
    else
      FF.Scanner.Start()
    end
  end)

  panel.TableSection = buildSection(content, "Potential Flips")
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
    { key = "itemName",         label = "Item Name",                   width = COL.Item,   defaultDir = "asc"  },
    { key = "relativeQuantity", label = "Relative Order Quantity (%)", width = COL.RelQty, defaultDir = "asc"  },
    { key = "sellSideDepth",    label = "Listings Depth (n)",          width = COL.Depth,  defaultDir = "desc" },
    { key = "totalCost",        label = "Investment (g)",              width = COL.Cost,   defaultDir = "asc"  },
    { key = "roi",              label = "ROI (%)",                     width = COL.ROI,    defaultDir = "desc" },
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
      if FF.sortProperty == def.key then
        FF.sortDirection = (FF.sortDirection == "asc") and "desc" or "asc"
      else
        FF.sortProperty = def.key
        FF.sortDirection = def.defaultDir
      end
      if FF.panel then
        FF.panel:RefreshSortIndicators()
        FF.panel:Render()
      end
    end)

    btn.sortKey = def.key
    return btn
  end

  local headerX = 0
  for _, def in ipairs(HEADER_COLS) do
    table.insert(panel.HeaderButtons, CreateSortHeader(def, headerX))
    headerX = headerX + def.width + COL.Gap
  end

  panel.Scroll = CreateFrame("ScrollFrame", "FlipperResultsScroll", tableBody)
  panel.Scroll:SetPoint("TOPLEFT", panel.HeaderRow, "BOTTOMLEFT", 0, -6)
  panel.Scroll:SetPoint("BOTTOMRIGHT", tableBody, "BOTTOMRIGHT", -SECTION_BODY_INSET - SCROLLBAR_W, 0)
  panel.Scroll:EnableMouseWheel(true)

  panel.Content = CreateFrame("Frame", nil, panel.Scroll)
  panel.Content:SetSize(C.PanelWidth - 2 * PAD_X - 2 * SECTION_INNER_PAD - 2 * SECTION_BODY_INSET - SCROLLBAR_W, 1)
  panel.Scroll:SetScrollChild(panel.Content)

  -- Native minimal scrollbar from the in-game Options panel (MinimalScrollBar).
  panel.ScrollScrollBar = CreateFrame("EventFrame", "FlipperScrollBar", tableBody, "MinimalScrollBar")
  panel.ScrollScrollBar:SetPoint("TOPLEFT", panel.Scroll, "TOPRIGHT", 4, -4)
  panel.ScrollScrollBar:SetPoint("BOTTOMLEFT", panel.Scroll, "BOTTOMRIGHT", 4, 7)
  panel.ScrollScrollBar:SetHideIfUnscrollable(true)
  panel.ScrollScrollBar:Init(1, 0.25)

  panel.ScrollScrollBar:RegisterCallback("OnScroll", function(_, scrollPercentage)
    local range = math.max(0, panel.Content:GetHeight() - panel.Scroll:GetHeight())
    panel.Scroll:SetVerticalScroll(range * scrollPercentage)
  end, panel.Scroll)

  panel.Scroll:SetScript("OnMouseWheel", function(_, delta)
    if not panel.ScrollScrollBar:HasScrollableExtent() then return end
    local pct = panel.ScrollScrollBar:GetScrollPercentage() - delta * 0.1
    panel.ScrollScrollBar:SetScrollPercentage(math.max(0, math.min(1, pct)))
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

  panel.StatusCenter = tableBody:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  panel.StatusCenter:SetPoint("TOPLEFT", panel.Scroll, "TOPLEFT", 0, 0)
  panel.StatusCenter:SetPoint("BOTTOMRIGHT", panel.Scroll, "BOTTOMRIGHT", 0, 0)
  panel.StatusCenter:SetJustifyH("CENTER")
  panel.StatusCenter:SetJustifyV("MIDDLE")
  panel.StatusCenter:SetWordWrap(false)
  panel.StatusCenter:SetTextColor(1, 0.82, 0, 1)
  panel.StatusCenter:Hide()

  panel.StatusFadeOut = CreateFrame("Frame", nil, panel)
  panel.StatusFadeOut:Hide()
  panel.StatusFadeOut:SetScript("OnUpdate", function(self, delta)
    self.elapsed = (self.elapsed or 0) + delta
    local t = self.elapsed
    if t < 1.5 then
      panel.StatusCenter:SetAlpha(1)
    elseif t < 1.8 then
      panel.StatusCenter:SetAlpha(1 - (t - 1.5) / 0.3)
    else
      panel.StatusCenter:SetAlpha(1)
      panel.StatusCenter:Hide()
      self:Hide()
      if FF.panel then FF.panel:Render() end
    end
  end)

  function panel:SetScanningUI(active)
    if active then
      self.ActionButton:SetText("Cancel Scan")
    else
      self.ActionButton:SetText("Find Potential Flips")
    end
  end

  function panel:ClearStatus()
    self.StatusFadeOut:Hide()
    self.StatusCenter:SetAlpha(1)
    self.StatusCenter:Hide()
  end

  function panel:SetStatus(text)
    if not text or text == "" then
      self:ClearStatus()
      return
    end
    self.StatusFadeOut:Hide()
    self.StatusCenter:SetText(text)
    self.StatusCenter:SetAlpha(1)
    self.StatusCenter:Show()
    self.StatusFadeOut.elapsed = 0
    self.StatusFadeOut:Show()
  end

  function panel:StartProgress(total)
    self.StatusFadeOut:Hide()
    self.StatusCenter:SetText(string.format("Searching: 0/%d", total))
    self.StatusCenter:SetAlpha(1)
    self.StatusCenter:Show()
  end

  function panel:UpdateProgress(scanned, total)
    self.StatusFadeOut:Hide()
    self.StatusCenter:SetText(string.format("Searching: %d/%d", scanned, total))
    self.StatusCenter:SetAlpha(1)
    self.StatusCenter:Show()
  end

  function panel:CompleteProgress(scanned, total)
    self.StatusFadeOut:Hide()
    self.StatusCenter:SetText(string.format("Searching: %d/%d  Complete", scanned, total))
    self.StatusCenter:SetAlpha(1)
    self.StatusCenter:Show()
    self.StatusFadeOut.elapsed = 0
    self.StatusFadeOut:Show()
  end

  function panel:RefreshSortIndicators()
    for _, btn in ipairs(self.HeaderButtons) do
      if FF.sortProperty == btn.sortKey then
        btn.Arrow:Show()
        if FF.sortDirection == "asc" then
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
    FF.Filters.SortFlips(FF.flips)

    local hasResults = #FF.flips > 0
    local statusVisible = self.StatusCenter:IsShown()

    if hasResults or statusVisible then
      self.EmptyMessage:Hide()
    else
      if FF.hasScanned then
        self.EmptyMessage:SetText("No flips found. Try adjusting your filters or broadening your shopping list search.")
      else
        self.EmptyMessage:SetText("Run a shopping list search in Auctionator, then click Find Potential Flips.")
      end
      self.EmptyMessage:Show()
    end

    for i, flip in ipairs(FF.flips) do
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

    for i = #FF.flips + 1, #self.rows do
      self.rows[i]:Hide()
      self.rows[i].flip = nil
    end

    local contentHeight = #FF.flips * C.RowHeight
    self.Content:SetHeight(math.max(contentHeight, 1))

    local viewport = self.Scroll:GetHeight()
    local visiblePct = math.min(1, viewport / math.max(contentHeight, 1))
    self.ScrollScrollBar:SetVisibleExtentPercentage(visiblePct)
    local range = math.max(0, contentHeight - viewport)
    self.Scroll:SetVerticalScroll(range * self.ScrollScrollBar:GetScrollPercentage())
  end

  FF.panel = panel
  return panel
end

function FF.Panel.Toggle()
  local panel = FF.panel or FF.Panel.Create()
  if not panel then return end

  if panel:IsShown() then
    panel:Hide()
    return
  end

  local ah = GetAHFrame()
  if ah then
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", ah, "TOPRIGHT", 10, 0)
  end
  panel:Show()
  panel:Render()
end
