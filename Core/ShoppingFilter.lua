FF.ShoppingFilter = {}

local STAT_ORDER = { "strength", "agility", "stamina", "intellect", "spirit" }

local STAT_LABELS = {
  strength  = _G.SPELL_STAT1_NAME or "Strength",
  agility   = _G.SPELL_STAT2_NAME or "Agility",
  stamina   = _G.SPELL_STAT3_NAME or "Stamina",
  intellect = _G.SPELL_STAT4_NAME or "Intellect",
  spirit    = _G.SPELL_STAT5_NAME or "Spirit",
}

-- Pre-lowered tokens for matching against the lowercased tooltip text the
-- StatScan parser returns.
local STAT_TOKENS = {}
for k, label in pairs(STAT_LABELS) do STAT_TOKENS[k] = label:lower() end

local DIALOG_WIDTH = 510
local PANEL_WIDTH = 150

-- The panel itself is the source of truth: its controls persist across dialog
-- opens (we don't reset them in OnShow's ResetAll path), and `active` is
-- rebuilt from the panel on every SearchStart so toggling a box takes effect
-- on the next search regardless of where it was triggered from.
local active = nil

local function ReadDraft(panel)
  local draft = { stats = {}, dpsMin = nil, any = false }
  for _, key in ipairs(STAT_ORDER) do
    if panel.statChecks[key]:GetChecked() then
      draft.stats[key] = true
      draft.any = true
    end
  end
  if panel.dpsCheck:GetChecked() then
    local n = tonumber(panel.dpsEdit:GetText())
    if n and n > 0 then
      draft.dpsMin = n
      draft.any = true
    end
  end
  return draft
end

local function ClearControls(panel)
  for _, key in ipairs(STAT_ORDER) do
    panel.statChecks[key]:SetChecked(false)
  end
  panel.dpsCheck:SetChecked(false)
  panel.dpsEdit:SetText("")
end

local function BuildPanel(dialog)
  if dialog.ffStatFilter then return dialog.ffStatFilter end

  dialog:SetWidth(DIALOG_WIDTH)

  local panel = CreateFrame("Frame", nil, dialog)
  panel:SetSize(PANEL_WIDTH, 200)
  panel:SetPoint("TOPRIGHT", dialog.Inset, "TOPRIGHT", -10, -8)

  local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  heading:SetPoint("TOPLEFT", 4, 0)
  heading:SetText("Filter by Stat")

  panel.statChecks = {}
  local previous = heading
  for index, key in ipairs(STAT_ORDER) do
    local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    check:SetSize(20, 20)
    if index == 1 then
      check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", -4, -4)
    else
      check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -2)
    end
    local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    label:SetText(STAT_LABELS[key])
    panel.statChecks[key] = check
    previous = check
  end

  local dpsCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  dpsCheck:SetSize(20, 20)
  dpsCheck:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -10)
  local dpsLabel = dpsCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  dpsLabel:SetPoint("LEFT", dpsCheck, "RIGHT", 2, 0)
  dpsLabel:SetText("Min DPS")

  local dpsEdit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  dpsEdit:SetSize(50, 20)
  dpsEdit:SetPoint("LEFT", dpsLabel, "RIGHT", 10, 0)
  dpsEdit:SetAutoFocus(false)
  dpsEdit:SetNumeric(true)
  dpsEdit:SetMaxLetters(4)
  dpsEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  dpsEdit:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    dialog:OnFinishedClicked()
  end)

  panel.dpsCheck = dpsCheck
  panel.dpsEdit = dpsEdit
  dialog.ffStatFilter = panel

  -- The dialog's "Reset All" button clears Auctionator's own fields via
  -- ResetAll(); auto-OnShow uses the same call, so we can't differentiate
  -- there. Hook the button itself so only an explicit click wipes our panel.
  if dialog.ResetAllButton then
    dialog.ResetAllButton:HookScript("OnClick", function()
      ClearControls(panel)
    end)
  end

  return panel
end

-- AddFinalResults only awaits the base item (Item:CreateFromItemID) before
-- calling CheckFilters; for random-suffix gear the variant tooltip can still
-- be sparse, so be lenient: include results whose link data isn't cached yet
-- to avoid dropping legitimate matches. Loads kicked off in ProcessSearchResults
-- mean repeat searches see the variant cached and filter cleanly.
function FF.ShoppingFilter.PassesFilter(resultWithKey)
  if not active then return true end

  local entries = resultWithKey and resultWithKey.entries
  local link = entries and entries[1] and entries[1].itemLink
  if not link then return false end

  local item = Item:CreateFromItemLink(link)
  if item and not item:IsItemEmpty() and not item:IsItemDataCached() then
    item:ContinueOnItemLoad(function() end)
    return true
  end

  local text = FF.StatScan.ReadItemText(link)
  if not text then return true end

  -- Plain substring match on the tooltip text, mirroring the old Stat Finder
  -- side panel. Structured parsing was too brittle: any stat line the regex
  -- didn't capture exactly (suffix gear, equip effects) silently dropped
  -- legitimate Agility/Stamina matches.
  for key in pairs(active.stats) do
    if not text:find(STAT_TOKENS[key], 1, true) then return false end
  end

  if active.dpsMin then
    local dps = FF.StatScan.ParseDPS(text)
    if not dps or dps < active.dpsMin then return false end
  end

  return true
end

local searchListener = {}
function searchListener:ReceiveEvent(eventName)
  if eventName ~= Auctionator.Shopping.Tab.Events.SearchStart then return end
  local dialog = _G.AuctionatorShoppingTabItemFrame
  local panel = dialog and dialog.ffStatFilter
  if not panel then active = nil; return end
  local draft = ReadDraft(panel)
  active = draft.any and draft or nil
end

function FF.ShoppingFilter.Hook()
  if FF.shoppingFilterHooked then return end
  local mixin = _G.AuctionatorShoppingItemMixin
  if not (mixin and Auctionator and Auctionator.Search
      and Auctionator.Search.CheckFilters and Auctionator.EventBus
      and Auctionator.Shopping and Auctionator.Shopping.Tab
      and Auctionator.Shopping.Tab.Events) then
    return
  end

  -- The dialog is created later (on AH open); hooking the mixin table now lets
  -- Mixin() copy our wrapped OnLoad onto the frame at creation time.
  hooksecurefunc(mixin, "OnLoad", function(self)
    if self ~= _G.AuctionatorShoppingTabItemFrame then return end
    BuildPanel(self)
  end)

  -- CheckFilters returns a boolean; replacing (rather than post-hooking) lets
  -- a failed stat/DPS check veto a result.
  local originalCheckFilters = Auctionator.Search.CheckFilters
  Auctionator.Search.CheckFilters = function(resultWithKey, filters)
    if not originalCheckFilters(resultWithKey, filters) then return false end
    return FF.ShoppingFilter.PassesFilter(resultWithKey)
  end

  -- Warm the suffix-variant cache as scan pages arrive so the tooltip read
  -- in PassesFilter has full stat lines by the time AddFinalResults fires.
  local providerMixin = _G.AuctionatorDirectSearchProviderMixin
  if providerMixin and providerMixin.ProcessSearchResults then
    hooksecurefunc(providerMixin, "ProcessSearchResults", function(_, pageResults)
      if type(pageResults) ~= "table" then return end
      for _, entry in ipairs(pageResults) do
        local link = entry.itemLink
        if link then
          local item = Item:CreateFromItemLink(link)
          if item and not item:IsItemEmpty() and not item:IsItemDataCached() then
            item:ContinueOnItemLoad(function() end)
          end
        end
      end
    end)
  end

  Auctionator.EventBus:RegisterSource(searchListener, "AuctionatorPlusShoppingFilter")
  Auctionator.EventBus:Register(searchListener, {
    Auctionator.Shopping.Tab.Events.SearchStart,
  })

  FF.shoppingFilterHooked = true
end
