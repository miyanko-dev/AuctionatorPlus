FF.Panel = {}

local C = FF.Constants
local COL = C.Columns

local tooltipBackdrop = {
  bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile     = true,
  tileSize = 8,
  edgeSize = 16,
  insets   = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function applyTooltipStyle(frame)
  if frame.SetBackdrop then
    frame:SetBackdrop(tooltipBackdrop)
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.97)
    frame:SetBackdropBorderColor(0.8, 0.8, 0.8, 0.9)
  end
end

local function InitRowWidgets(row)
  if row.initialized then return end
  row.initialized = true
  row:SetHeight(C.RowHeight)

  local sep = row:CreateTexture(nil, "ARTWORK")
  sep:SetHeight(1)
  sep:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
  sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  sep:SetColorTexture(0.8, 0.8, 0.8, 0.08)

  row.Item = CreateFrame("Button", nil, row)
  row.Item:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.Item:SetSize(COL.Item, C.RowHeight)
  row.Item:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.Item.Text = row.Item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.Item.Text:SetPoint("LEFT", 0, 0)
  row.Item.Text:SetPoint("RIGHT", -4, 0)
  row.Item.Text:SetJustifyH("LEFT")
  row.Item.Text:SetWordWrap(false)

  local qtyX = COL.Item + COL.Gap
  row.Quantity = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.Quantity:SetPoint("LEFT", qtyX, 0)
  row.Quantity:SetWidth(COL.Qty)
  row.Quantity:SetJustifyH("LEFT")

  local orderX = qtyX + COL.Qty + COL.Gap
  row.OrderQty = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.OrderQty:SetPoint("LEFT", orderX, 0)
  row.OrderQty:SetWidth(COL.Order)
  row.OrderQty:SetJustifyH("LEFT")

  local costX = orderX + COL.Order + COL.Gap
  row.TotalCost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.TotalCost:SetPoint("LEFT", costX, 0)
  row.TotalCost:SetWidth(COL.Cost)
  row.TotalCost:SetJustifyH("LEFT")

  local profitX = costX + COL.Cost + COL.Gap
  row.Profit = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.Profit:SetPoint("LEFT", profitX, 0)
  row.Profit:SetWidth(COL.Profit)
  row.Profit:SetJustifyH("LEFT")
  row.Profit:SetTextColor(0.3, 1, 0.3)

  row.Item:SetScript("OnEnter", function(self)
    if row.flip and row.flip.itemLink then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(row.flip.itemLink)
      GameTooltip:Show()
    end
  end)
  row.Item:SetScript("OnLeave", GameTooltip_Hide)
  row.Item:SetScript("OnClick", function(_, button)
    if not row.flip then return end
    if button == "RightButton" and row.flip.itemLink then
      if IsModifiedClick("CHATLINK") then
        ChatEdit_InsertLink(row.flip.itemLink)
      end
    else
      if FF.Adapter and FF.Adapter.OpenFlipDetails then
        FF.Adapter.OpenFlipDetails(row.flip)
      end
    end
  end)
end

local function UpdateRow(row, flip)
  row.flip = flip
  local text = flip.itemLink or flip.itemName or "?"
  row.Item.Text:SetText(FF.Format.CleanItemText(text))
  row.Quantity:SetText(string.format("%.0f", flip.displayQuantity))
  row.OrderQty:SetText(string.format("%.0f", flip.totalQuantity))
  row.TotalCost:SetText(FF.Format.Money(flip.totalCost))
  row.Profit:SetText(FF.Format.Money(flip.margin))
end

local function MakeFader(panel, target)
  local fader = CreateFrame("Frame", nil, panel)
  fader:Hide()
  fader:SetScript("OnUpdate", function(self, delta)
    self.elapsed = (self.elapsed or 0) + delta
    local t = self.elapsed
    local alpha
    if t < 0.2 then
      alpha = t / 0.2
    elseif t < 3.8 then
      alpha = 1
    elseif t < 4.0 then
      alpha = 1 - (t - 3.8) / 0.2
    else
      alpha = 0
      self:Hide()
    end
    target:SetAlpha(alpha)
  end)
  return fader
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

  applyTooltipStyle(panel)

  local PAD = 12
  local GAP = 10
  local ROW_H = 24
  local SCROLLBAR_W = 16
  local HEADING_H = 16
  local HEADING_GAP = 8
  local LABEL_H = 14
  local LABEL_GAP = 2
  local INPUT_INSET = 5
  local FIELD_GAP = 20

  local function NewSeparator()
    local line = panel:CreateTexture(nil, "OVERLAY")
    line:SetHeight(1)
    line:SetColorTexture(0.8, 0.8, 0.8, 0.2)
    return line
  end

  panel.Title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.Title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -PAD)
  panel.Title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -PAD)
  panel.Title:SetHeight(ROW_H)
  panel.Title:SetJustifyH("LEFT")
  panel.Title:SetJustifyV("MIDDLE")
  panel.Title:SetText("Search for potential flips")
  panel.Title:SetTextColor(1, 1, 1, 1)

  local sepAfterTitle = NewSeparator()
  sepAfterTitle:SetPoint("TOPLEFT", panel.Title, "BOTTOMLEFT", 0, -GAP)
  sepAfterTitle:SetPoint("TOPRIGHT", panel.Title, "BOTTOMRIGHT", 0, -GAP)

  local FILTER_H = HEADING_H + HEADING_GAP + LABEL_H + LABEL_GAP + ROW_H

  panel.FilterRow = CreateFrame("Frame", nil, panel)
  panel.FilterRow:SetHeight(FILTER_H)
  panel.FilterRow:SetPoint("LEFT", panel, "LEFT", PAD, 0)
  panel.FilterRow:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
  panel.FilterRow:SetPoint("TOP", sepAfterTitle, "BOTTOM", 0, -GAP)

  panel.FilterHeading = panel.FilterRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.FilterHeading:SetPoint("TOPLEFT", panel.FilterRow, "TOPLEFT", 0, 0)
  panel.FilterHeading:SetJustifyH("LEFT")
  panel.FilterHeading:SetText("Filter")
  panel.FilterHeading:SetTextColor(1, 1, 1, 1)

  local FILTER_INNER_W = C.PanelWidth - 2 * PAD - 2 * INPUT_INSET
  local FILTER_FIELDS = 7
  local FILTER_FIELD_W = 95
  local FILTER_FIELD_GAP = (FILTER_INNER_W - FILTER_FIELDS * FILTER_FIELD_W) / (FILTER_FIELDS - 1)
  local FILTER_LABEL_START_Y = -HEADING_H - HEADING_GAP

  local function FilterFieldX(index)
    return INPUT_INSET + (index - 1) * (FILTER_FIELD_W + FILTER_FIELD_GAP)
  end

  local function CreateFilterField(index, labelText, maxLetters, defaultText)
    local label = panel.FilterRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", panel.FilterRow, "TOPLEFT", FilterFieldX(index), FILTER_LABEL_START_Y)
    label:SetWidth(FILTER_FIELD_W)
    label:SetJustifyH("LEFT")
    label:SetText(labelText)
    label:SetTextColor(0.7, 0.7, 0.7, 1)

    local edit = CreateFrame("EditBox", nil, panel.FilterRow, "InputBoxTemplate")
    edit:SetSize(FILTER_FIELD_W, ROW_H)
    edit:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -LABEL_GAP)
    edit:SetAutoFocus(false)
    edit:SetNumeric(true)
    edit:SetMaxLetters(maxLetters)
    edit:SetText(defaultText or "")
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnTextChanged", function()
      if FF.hasScanned then FF.Filters.RebuildAll() end
    end)
    return label, edit
  end

  panel.MinQuantityLabel,  panel.MinQuantityEditBox  = CreateFilterField(1, "Min Listed Qty (n)",  6,  "1")
  panel.MaxOrderQtyLabel,  panel.MaxOrderQtyEditBox  = CreateFilterField(2, "Max Order Qty (n)",   6,  "")
  panel.MaxQtyPctLabel,    panel.MaxQtyPctEditBox    = CreateFilterField(3, "Max Order Qty (%)",   3,  "")
  panel.MaxInvestLabel,    panel.MaxInvestEditBox    = CreateFilterField(4, "Max Invest (g)",      10, "")
  panel.MinProfitLabel,    panel.MinProfitEditBox    = CreateFilterField(5, "Min Profit (g)",      10, "")
  panel.MinMarginLabel,    panel.MinMarginEditBox    = CreateFilterField(6, "Min Margin (%)",      3,
    tostring(math.floor((C.PriceJumpRatio - 1) * 100 + 0.5)))
  panel.AHCutLabel,        panel.AHCutEditBox        = CreateFilterField(7, "AH Cut (%)",          3,
    tostring(C.DefaultAHCutPercent))

  local sepAfterFilter = NewSeparator()
  sepAfterFilter:SetPoint("TOPLEFT", panel.FilterRow, "BOTTOMLEFT", 0, -GAP)
  sepAfterFilter:SetPoint("TOPRIGHT", panel.FilterRow, "BOTTOMRIGHT", 0, -GAP)

  local SORT_DROPDOWN_H = 24
  local SORT_H = HEADING_H + HEADING_GAP + LABEL_H + LABEL_GAP + SORT_DROPDOWN_H

  panel.SortRow = CreateFrame("Frame", nil, panel)
  panel.SortRow:SetHeight(SORT_H)
  panel.SortRow:SetPoint("LEFT", panel, "LEFT", PAD, 0)
  panel.SortRow:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
  panel.SortRow:SetPoint("TOP", sepAfterFilter, "BOTTOM", 0, -GAP)

  panel.SortHeading = panel.SortRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.SortHeading:SetPoint("TOPLEFT", panel.SortRow, "TOPLEFT", 0, 0)
  panel.SortHeading:SetJustifyH("LEFT")
  panel.SortHeading:SetText("Sort")
  panel.SortHeading:SetTextColor(1, 1, 1, 1)

  panel.SortPropertyLabel = panel.SortRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.SortPropertyLabel:SetPoint("TOPLEFT", panel.SortRow, "TOPLEFT", INPUT_INSET, -HEADING_H - HEADING_GAP)
  panel.SortPropertyLabel:SetJustifyH("LEFT")
  panel.SortPropertyLabel:SetText("Sort by")
  panel.SortPropertyLabel:SetTextColor(0.7, 0.7, 0.7, 1)

  panel.SortPropertyDD = FF.Adapter.CreateDropdown(
    panel.SortRow, 180, C.SortOptions,
    function() return FF.sortProperty end,
    function(key) FF.sortProperty = key; if FF.panel then FF.panel:Render() end end
  )
  panel.SortPropertyDD:SetPoint("TOPLEFT", panel.SortPropertyLabel, "BOTTOMLEFT", 0, -LABEL_GAP)

  panel.SortDirectionLabel = panel.SortRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.SortDirectionLabel:SetPoint("TOPLEFT", panel.SortRow, "TOPLEFT", INPUT_INSET + 180 + FIELD_GAP, -HEADING_H - HEADING_GAP)
  panel.SortDirectionLabel:SetJustifyH("LEFT")
  panel.SortDirectionLabel:SetText("Direction")
  panel.SortDirectionLabel:SetTextColor(0.7, 0.7, 0.7, 1)

  panel.SortDirectionDD = FF.Adapter.CreateDropdown(
    panel.SortRow, 140, C.SortDirections,
    function() return FF.sortDirection end,
    function(key) FF.sortDirection = key; if FF.panel then FF.panel:Render() end end
  )
  panel.SortDirectionDD:SetPoint("TOPLEFT", panel.SortDirectionLabel, "BOTTOMLEFT", 0, -LABEL_GAP)

  local sepAfterSort = NewSeparator()
  sepAfterSort:SetPoint("TOPLEFT", panel.SortRow, "BOTTOMLEFT", 0, -GAP)
  sepAfterSort:SetPoint("TOPRIGHT", panel.SortRow, "BOTTOMRIGHT", 0, -GAP)

  panel.HeaderRow = CreateFrame("Frame", nil, panel)
  panel.HeaderRow:SetHeight(ROW_H)
  panel.HeaderRow:SetPoint("LEFT", panel, "LEFT", PAD, 0)
  panel.HeaderRow:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
  panel.HeaderRow:SetPoint("TOP", sepAfterSort, "BOTTOM", 0, -GAP)

  local function AddHeader(text, x, width)
    local fs = panel.HeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", panel.HeaderRow, "LEFT", x, 0)
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    fs:SetTextColor(0.7, 0.7, 0.7, 1)
    return fs
  end

  local qtyX    = COL.Item + COL.Gap
  local orderX  = qtyX + COL.Qty + COL.Gap
  local costX   = orderX + COL.Order + COL.Gap
  local profitX = costX + COL.Cost + COL.Gap

  AddHeader("Item Name", 0,       COL.Item)
  AddHeader("Listed Qty", qtyX,   COL.Qty)
  AddHeader("Order Qty",  orderX, COL.Order)
  AddHeader("Invest",     costX,  COL.Cost)
  AddHeader("Profit",     profitX, COL.Profit)

  panel.ActionsRow = CreateFrame("Frame", nil, panel)
  panel.ActionsRow:SetHeight(ROW_H)
  panel.ActionsRow:SetPoint("LEFT", panel, "LEFT", PAD, 0)
  panel.ActionsRow:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
  panel.ActionsRow:SetPoint("BOTTOM", panel, "BOTTOM", 0, PAD)

  panel.FlipScanBtn = CreateFrame("Button", nil, panel.ActionsRow, "UIPanelButtonTemplate")
  panel.FlipScanBtn:SetSize(120, ROW_H)
  panel.FlipScanBtn:SetPoint("RIGHT", panel.ActionsRow, "RIGHT", 0, 0)
  panel.FlipScanBtn:SetText("Find Flips")
  panel.FlipScanBtn:GetFontString():SetTextColor(1, 0.82, 0)
  panel.FlipScanBtn:SetScript("OnClick", function() FF.Scanner.Start() end)

  panel.CancelBtn = CreateFrame("Button", nil, panel.ActionsRow, "UIPanelButtonTemplate")
  panel.CancelBtn:SetSize(80, ROW_H)
  panel.CancelBtn:SetPoint("RIGHT", panel.FlipScanBtn, "LEFT", -8, 0)
  panel.CancelBtn:SetText(CANCEL)
  panel.CancelBtn:GetFontString():SetTextColor(1, 0.82, 0)
  panel.CancelBtn:SetScript("OnClick", function() FF.Scanner.Abort() end)
  panel.CancelBtn:Hide()

  panel.StatusLeft = panel.ActionsRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  do
    local fontFile, _, fontFlags = panel.StatusLeft:GetFont()
    panel.StatusLeft:SetFont(fontFile, 14, fontFlags)
  end
  panel.StatusLeft:SetPoint("LEFT", panel.ActionsRow, "LEFT", 4, 0)
  panel.StatusLeft:SetPoint("RIGHT", panel.CancelBtn, "LEFT", -8, 0)
  panel.StatusLeft:SetHeight(ROW_H)
  panel.StatusLeft:SetJustifyH("LEFT")
  panel.StatusLeft:SetJustifyV("MIDDLE")
  panel.StatusLeft:SetText("")
  panel.StatusLeft:SetTextColor(1, 1, 1, 1)
  panel.StatusLeft:SetAlpha(0)

  panel.StatusFader = MakeFader(panel, panel.StatusLeft)

  panel.ProgressFadeIn = CreateFrame("Frame", nil, panel)
  panel.ProgressFadeIn:Hide()
  panel.ProgressFadeIn:SetScript("OnUpdate", function(self, delta)
    self.elapsed = (self.elapsed or 0) + delta
    if self.elapsed < 0.2 then
      panel.StatusLeft:SetAlpha(self.elapsed / 0.2)
    else
      panel.StatusLeft:SetAlpha(1)
      self:Hide()
    end
  end)

  panel.ProgressFadeOut = CreateFrame("Frame", nil, panel)
  panel.ProgressFadeOut:Hide()
  panel.ProgressFadeOut:SetScript("OnUpdate", function(self, delta)
    self.elapsed = (self.elapsed or 0) + delta
    local t = self.elapsed
    if t < 4.0 then
      panel.StatusLeft:SetAlpha(1)
    elseif t < 4.2 then
      panel.StatusLeft:SetAlpha(1 - (t - 4.0) / 0.2)
    else
      panel.StatusLeft:SetAlpha(0)
      self:Hide()
    end
  end)

  local sepBeforeActions = NewSeparator()
  sepBeforeActions:SetPoint("LEFT", panel, "LEFT", PAD, 0)
  sepBeforeActions:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
  sepBeforeActions:SetPoint("BOTTOM", panel.ActionsRow, "TOP", 0, GAP)

  panel.Scroll = CreateFrame("ScrollFrame", "FlipperResultsScroll", panel)
  panel.Scroll:SetPoint("TOPLEFT", panel.HeaderRow, "BOTTOMLEFT", 0, -GAP)
  panel.Scroll:SetPoint("BOTTOMRIGHT", sepBeforeActions, "TOPRIGHT", -SCROLLBAR_W, GAP)
  panel.Scroll:EnableMouseWheel(true)

  panel.Content = CreateFrame("Frame", nil, panel.Scroll)
  panel.Content:SetSize(C.PanelWidth - 2 * PAD - SCROLLBAR_W, 1)
  panel.Scroll:SetScrollChild(panel.Content)

  panel.ScrollScrollBar = CreateFrame("Slider", "FlipperScrollBar", panel, "UIPanelScrollBarTemplate")
  panel.ScrollScrollBar:SetPoint("TOPLEFT", panel.Scroll, "TOPRIGHT", 4, -16)
  panel.ScrollScrollBar:SetPoint("BOTTOMLEFT", panel.Scroll, "BOTTOMRIGHT", 4, 16)
  panel.ScrollScrollBar:SetWidth(SCROLLBAR_W)
  panel.ScrollScrollBar:SetMinMaxValues(0, 1)
  panel.ScrollScrollBar:SetValueStep(0.01)
  panel.ScrollScrollBar:Hide()

  panel.ScrollScrollBar:SetScript("OnValueChanged", function(self, value)
    local range = math.max(0, panel.Content:GetHeight() - panel.Scroll:GetHeight())
    panel.Scroll:SetVerticalScroll(range * value)
  end)

  panel.Scroll:SetScript("OnMouseWheel", function(_, delta)
    if panel.ScrollScrollBar:IsShown() then
      local current = panel.ScrollScrollBar:GetValue()
      local step = 0.05
      panel.ScrollScrollBar:SetValue(math.max(0, math.min(1, current - delta * step)))
    end
  end)

  panel.rows = {}

  panel.EmptyMessage = panel.Scroll:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.EmptyMessage:SetPoint("TOPLEFT", panel.Scroll, "TOPLEFT", PAD, 0)
  panel.EmptyMessage:SetPoint("BOTTOMRIGHT", panel.Scroll, "BOTTOMRIGHT", -PAD, 0)
  panel.EmptyMessage:SetJustifyH("CENTER")
  panel.EmptyMessage:SetJustifyV("MIDDLE")
  panel.EmptyMessage:SetWordWrap(true)
  panel.EmptyMessage:SetText("Run a shopping list search in Auctionator, then click Find Flips.")
  panel.EmptyMessage:SetTextColor(0.5, 0.5, 0.5, 1)

  local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  closeBtn:SetSize(24, 24)
  closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 4, 4)
  closeBtn:SetFrameLevel(panel:GetFrameLevel() + 10)
  closeBtn:SetScript("OnClick", function() panel:Hide() end)

  function panel:SetScanningUI(active)
    self.CancelBtn:SetShown(active and true or false)
  end

  function panel:ClearStatus()
    self.StatusFader:Hide()
    self.ProgressFadeIn:Hide()
    self.ProgressFadeOut:Hide()
    self.StatusLeft:SetText("")
    self.StatusLeft:SetAlpha(0)
  end

  function panel:SetStatus(text)
    if not text or text == "" then
      self:ClearStatus()
      return
    end
    self.ProgressFadeIn:Hide()
    self.ProgressFadeOut:Hide()
    self.StatusLeft:SetText(text)
    self.StatusFader.elapsed = 0
    self.StatusFader:Show()
  end

  function panel:StartProgress(total)
    self.StatusFader:Hide()
    self.ProgressFadeOut:Hide()
    self.StatusLeft:SetText(string.format("Scanning: 0/%d", total))
    self.StatusLeft:SetAlpha(0)
    self.ProgressFadeIn.elapsed = 0
    self.ProgressFadeIn:Show()
  end

  function panel:UpdateProgress(scanned, total)
    self.StatusFader:Hide()
    self.ProgressFadeOut:Hide()
    self.StatusLeft:SetText(string.format("Scanning: %d/%d", scanned, total))
  end

  function panel:CompleteProgress(scanned, total)
    self.StatusFader:Hide()
    self.ProgressFadeIn:Hide()
    self.StatusLeft:SetText(string.format("Scanning: %d/%d |cff40ff40Complete|r", scanned, total))
    self.StatusLeft:SetAlpha(1)
    self.ProgressFadeOut.elapsed = 0
    self.ProgressFadeOut:Show()
  end

  function panel:Render()
    FF.Filters.SortFlips(FF.flips)

    if #FF.flips == 0 then
      if FF.hasScanned then
        self.EmptyMessage:SetText("No flips found. Try adjusting your filters or broadening your shopping list search.")
      else
        self.EmptyMessage:SetText("Run a shopping list search in Auctionator, then click Find Flips.")
      end
      self.EmptyMessage:Show()
    else
      self.EmptyMessage:Hide()
    end

    for i, flip in ipairs(FF.flips) do
      local row = self.rows[i]
      if not row then
        row = CreateFrame("Frame", nil, self.Content)
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

    local visibleHeight = self.Scroll:GetHeight()
    if contentHeight > visibleHeight then
      self.ScrollScrollBar:Show()
    else
      self.Scroll:SetVerticalScroll(0)
      self.ScrollScrollBar:Hide()
    end
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
