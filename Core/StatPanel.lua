FF.StatPanel = {}

local SP = FF.Constants.StatPanel

local PAD_X = 16
local PAD_TOP = 52
local PAD_BOTTOM = 16
local SECTION_GAP = 22
local SECTION_INNER_PAD = 12
local SECTION_LABEL_LIFT = 7
local SECTION_BODY_INSET = 4
local ACTION_BUTTON_W = 180
local ACTION_BUTTON_H = 24
local ACTION_AREA_H = ACTION_BUTTON_H + 12
local INPUT_H = 24
local INPUT_HELPER_H = 28
local INPUT_HELPER_GAP = 6
local INPUT_LABEL_H = 14
local INPUT_LABEL_GAP = 2
local SCROLLBAR_W = 16

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
  row:SetHeight(SP.RowHeight)

  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(row)
  highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  highlight:SetBlendMode("ADD")

  row.ItemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.ItemText:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.ItemText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  row.ItemText:SetJustifyH("LEFT")
  row.ItemText:SetWordWrap(false)

  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnEnter", function(self)
    if self.match and self.match.itemLink then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(self.match.itemLink)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", GameTooltip_Hide)
  row:SetScript("OnClick", function(self, button)
    if not self.match then return end
    if button == "RightButton" then
      if IsModifiedClick("CHATLINK") and self.match.itemLink then
        ChatEdit_InsertLink(self.match.itemLink)
      end
    else
      if FF.Adapter and FF.Adapter.OpenFlipDetails then
        FF.Adapter.OpenFlipDetails({
          entry    = self.match.entry,
          itemLink = self.match.itemLink,
          itemName = self.match.itemLink and GetItemInfo(self.match.itemLink),
        })
      end
    end
  end)
end

local function UpdateRow(row, match)
  row.match = match
  local label = match.itemLink or "?"
  row.ItemText:SetText(FF.Format.CleanItemText(label))
end

local function GetAHFrame()
  if FF.Adapter and FF.Adapter.GetAHFrame then
    return FF.Adapter.GetAHFrame()
  end
  return nil
end

function FF.StatPanel.Create()
  if FF.statPanel then return FF.statPanel end
  if not GetAHFrame() then return nil end

  local panel = CreateFrame("Frame", "FlipperStatPanel", UIParent, "BackdropTemplate")
  panel:SetSize(SP.Width, SP.Height)
  panel:SetPoint("CENTER")
  panel:SetFrameStrata("FULLSCREEN_DIALOG")
  panel:SetFrameLevel(1000)
  panel:EnableMouse(true)
  panel:SetMovable(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:Hide()

  if panel.SetBackdrop then panel:SetBackdrop(PANEL_BACKDROP) end
  buildTitleHeader(panel, "Stat Finder")

  local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
  closeBtn:SetScript("OnClick", function() panel:Hide() end)

  local content = CreateFrame("Frame", nil, panel)
  content:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD_X, -PAD_TOP)
  content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD_X, PAD_BOTTOM)

  local INPUT_SECTION_BODY_H = INPUT_LABEL_H + INPUT_LABEL_GAP + INPUT_H + INPUT_HELPER_GAP + INPUT_HELPER_H
  local INPUT_SECTION_H = INPUT_SECTION_BODY_H + 2 * SECTION_INNER_PAD

  panel.InputSection = buildSection(content, "Stat Terms")
  panel.InputSection:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  panel.InputSection:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
  panel.InputSection:SetHeight(INPUT_SECTION_H)

  local inputBody = panel.InputSection.body

  panel.InputLabel = inputBody:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.InputLabel:SetPoint("TOPLEFT", inputBody, "TOPLEFT", SECTION_BODY_INSET, 0)
  panel.InputLabel:SetPoint("TOPRIGHT", inputBody, "TOPRIGHT", -SECTION_BODY_INSET, 0)
  panel.InputLabel:SetHeight(INPUT_LABEL_H)
  panel.InputLabel:SetJustifyH("LEFT")
  panel.InputLabel:SetWordWrap(false)
  panel.InputLabel:SetText("Stats (comma-separated)")
  panel.InputLabel:SetTextColor(0.85, 0.85, 0.85, 1)

  panel.InputBox = CreateFrame("EditBox", nil, inputBody, "InputBoxTemplate")
  panel.InputBox:SetPoint("TOPLEFT", panel.InputLabel, "BOTTOMLEFT", 5, -INPUT_LABEL_GAP)
  panel.InputBox:SetPoint("TOPRIGHT", panel.InputLabel, "BOTTOMRIGHT", -5, -INPUT_LABEL_GAP)
  panel.InputBox:SetHeight(INPUT_H)
  panel.InputBox:SetAutoFocus(false)
  panel.InputBox:SetMaxLetters(SP.InputMaxLetters)
  panel.InputBox:SetText(FF.statQuery or "")
  panel.InputBox:SetScript("OnTextChanged", function(self)
    FF.statQuery = self:GetText() or ""
  end)
  panel.InputBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  panel.InputBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    FF.StatFilter.Run(self:GetText() or "")
  end)

  panel.InputHelper = inputBody:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.InputHelper:SetPoint("TOPLEFT", panel.InputBox, "BOTTOMLEFT", -5, -INPUT_HELPER_GAP)
  panel.InputHelper:SetPoint("TOPRIGHT", panel.InputBox, "BOTTOMRIGHT", 5, -INPUT_HELPER_GAP)
  panel.InputHelper:SetHeight(INPUT_HELPER_H)
  panel.InputHelper:SetJustifyH("LEFT")
  panel.InputHelper:SetJustifyV("TOP")
  panel.InputHelper:SetWordWrap(true)
  panel.InputHelper:SetText("Matches Auctionator shopping results whose tooltip contains every term. Use the words your client shows; aliases for primary stats and DPS are pre-translated.")
  panel.InputHelper:SetTextColor(0.55, 0.55, 0.55, 1)

  panel.ActionButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  panel.ActionButton:SetSize(ACTION_BUTTON_W, ACTION_BUTTON_H)
  panel.ActionButton:SetPoint("BOTTOM", content, "BOTTOM", 0, 0)
  panel.ActionButton:SetText("Find Matches")
  panel.ActionButton:GetFontString():SetTextColor(1, 0.82, 0)
  panel.ActionButton:SetScript("OnClick", function()
    if FF.StatFilter.running then
      FF.StatFilter.Abort()
    else
      FF.StatFilter.Run(panel.InputBox:GetText() or "")
    end
  end)

  panel.TableSection = buildSection(content, "Matches")
  panel.TableSection:SetPoint("TOPLEFT", panel.InputSection, "BOTTOMLEFT", 0, -SECTION_GAP)
  panel.TableSection:SetPoint("TOPRIGHT", panel.InputSection, "BOTTOMRIGHT", 0, -SECTION_GAP)
  panel.TableSection:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, ACTION_AREA_H)
  panel.TableSection:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, ACTION_AREA_H)

  local tableBody = panel.TableSection.body

  panel.Scroll = CreateFrame("ScrollFrame", "FlipperStatScroll", tableBody)
  panel.Scroll:SetPoint("TOPLEFT", tableBody, "TOPLEFT", SECTION_BODY_INSET, 0)
  panel.Scroll:SetPoint("BOTTOMRIGHT", tableBody, "BOTTOMRIGHT", -SECTION_BODY_INSET - SCROLLBAR_W, 0)
  panel.Scroll:EnableMouseWheel(true)

  panel.Content = CreateFrame("Frame", nil, panel.Scroll)
  panel.Content:SetSize(SP.Width - 2 * PAD_X - 2 * SECTION_INNER_PAD - 2 * SECTION_BODY_INSET - SCROLLBAR_W, 1)
  panel.Scroll:SetScrollChild(panel.Content)

  panel.ScrollBar = CreateFrame("EventFrame", "FlipperStatScrollBar", tableBody, "MinimalScrollBar")
  panel.ScrollBar:SetPoint("TOPLEFT", panel.Scroll, "TOPRIGHT", 4, -4)
  panel.ScrollBar:SetPoint("BOTTOMLEFT", panel.Scroll, "BOTTOMRIGHT", 4, 7)
  panel.ScrollBar:SetHideIfUnscrollable(true)
  panel.ScrollBar:Init(1, 0.25)

  panel.ScrollBar:RegisterCallback("OnScroll", function(_, pct)
    local range = math.max(0, panel.Content:GetHeight() - panel.Scroll:GetHeight())
    panel.Scroll:SetVerticalScroll(range * pct)
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
  panel.EmptyMessage:SetText("Run a shopping list search in Auctionator, then enter stats above and click Find Matches.")

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
      if FF.statPanel then FF.statPanel:Render() end
    end
  end)

  function panel:SetRunningUI(active)
    if active then
      self.ActionButton:SetText("Cancel Search")
    else
      self.ActionButton:SetText("Find Matches")
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

  function panel:Render()
    local matches = FF.statMatches or {}
    local hasResults = #matches > 0
    local statusVisible = self.StatusCenter:IsShown()

    if hasResults or statusVisible then
      self.EmptyMessage:Hide()
    else
      if FF.StatFilter.scannedCount > 0 then
        self.EmptyMessage:SetText("No items matched. Try broader terms or run a wider shopping search.")
      else
        self.EmptyMessage:SetText("Run a shopping list search in Auctionator, then enter stats above and click Find Matches.")
      end
      self.EmptyMessage:Show()
    end

    for i, match in ipairs(matches) do
      local row = self.rows[i]
      if not row then
        row = CreateFrame("Button", nil, self.Content)
        row:SetHeight(SP.RowHeight)
        row:SetPoint("TOPLEFT",  self.Content, "TOPLEFT",  0, -(i - 1) * SP.RowHeight)
        row:SetPoint("TOPRIGHT", self.Content, "TOPRIGHT", 0, -(i - 1) * SP.RowHeight)
        InitRowWidgets(row)
        self.rows[i] = row
      end
      UpdateRow(row, match)
      row:Show()
    end

    for i = #matches + 1, #self.rows do
      self.rows[i]:Hide()
      self.rows[i].match = nil
    end

    local contentHeight = #matches * SP.RowHeight
    self.Content:SetHeight(math.max(contentHeight, 1))

    local viewport = self.Scroll:GetHeight()
    local visiblePct = math.min(1, viewport / math.max(contentHeight, 1))
    self.ScrollBar:SetVisibleExtentPercentage(visiblePct)
    local range = math.max(0, contentHeight - viewport)
    self.Scroll:SetVerticalScroll(range * self.ScrollBar:GetScrollPercentage())
  end

  FF.statPanel = panel
  return panel
end

function FF.StatPanel.Toggle()
  local panel = FF.statPanel or FF.StatPanel.Create()
  if not panel then return end

  if panel:IsShown() then
    panel:Hide()
    return
  end

  panel:ClearAllPoints()
  local flipPanel = FF.panel
  if flipPanel and flipPanel:IsShown() then
    panel:SetPoint("TOPLEFT", flipPanel, "TOPRIGHT", 6, 0)
  else
    local ah = GetAHFrame()
    if ah then
      panel:SetPoint("TOPLEFT", ah, "TOPRIGHT", 10, 0)
    else
      panel:SetPoint("CENTER")
    end
  end
  panel:Show()
  panel:Render()
end
