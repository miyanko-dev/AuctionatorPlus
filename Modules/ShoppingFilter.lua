local _, AP = ...

AP.ShoppingFilter = {}

local STAT_ORDER = AP.StatScan.STAT_ORDER
local STAT_LABELS = AP.StatScan.STAT_LABELS
local STAT_TOKENS = AP.StatScan.STAT_TOKENS

local DIALOG_WIDTH = 510
local PANEL_WIDTH = 150

-- The stat filter must affect only a search launched from the advanced dialog. `pending` is armed when the dialog's search button is clicked and consumed by that search's SearchStart; a normal search leaves it nil, so it is never filtered.
local active = nil
local pending = nil

local function readDraft(panel)
    local draft = { stats = {}, dpsMin = nil, any = false, logic = panel.statLogic }
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

local function clearControls(panel)
    for _, key in ipairs(STAT_ORDER) do
        panel.statChecks[key]:SetChecked(false)
    end
    panel.dpsCheck:SetChecked(false)
    panel.dpsEdit:SetText("")
    panel.statLogic = "AND"
    -- GenerateMenu re-runs the radio setup so the button text reflects the reset value.
    panel.logicDropdown:GenerateMenu()
end

local function buildPanel(dialog)
    if dialog.auctionatorPlusStatFilter then return end

    dialog:SetWidth(DIALOG_WIDTH)

    local panel = CreateFrame("Frame", nil, dialog)
    panel:SetSize(PANEL_WIDTH, 200)
    panel:SetPoint("TOPRIGHT", dialog.Inset, "TOPRIGHT", -10, -8)

    local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    heading:SetPoint("TOPLEFT", 4, 0)
    heading:SetText("Filter by Stat")

    -- AND is the historical behavior, so it stays the default after every reset.
    panel.statLogic = "AND"
    local logicDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    logicDropdown:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", -2, -4)
    logicDropdown:SetWidth(120)
    MenuUtil.CreateRadioMenu(logicDropdown,
        function(value) return panel.statLogic == value end,
        function(value) panel.statLogic = value end,
        { "Match All", "AND" },
        { "Match Any", "OR" })
    panel.logicDropdown = logicDropdown

    panel.statChecks = {}
    local previous = logicDropdown
    for index, key in ipairs(STAT_ORDER) do
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetSize(20, 20)
        if index == 1 then
            check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", -2, -4)
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
    dialog.auctionatorPlusStatFilter = panel

    -- Clear the checkboxes whenever the dialog closes, so a later normal search is never filtered by leftover boxes.
    dialog:HookScript("OnHide", function()
        clearControls(panel)
    end)

    -- Hook the button, not ResetAll(): auto-OnShow calls ResetAll too, and only an explicit click should wipe the panel.
    if dialog.ResetAllButton then
        dialog.ResetAllButton:HookScript("OnClick", function()
            clearControls(panel)
        end)
    end
end

-- Keep results whose link data is not cached yet rather than drop a legitimate match: random-suffix tooltips can be sparse when CheckFilters runs; loads kicked off in ProcessSearchResults let repeat searches filter cleanly.
function AP.ShoppingFilter.PassesFilter(resultWithKey)
    if not active then return true end

    local entries = resultWithKey and resultWithKey.entries
    local link = entries and entries[1] and entries[1].itemLink
    if not link then return false end

    local resultItem = Item:CreateFromItemLink(link)
    if resultItem and not resultItem:IsItemEmpty() and not resultItem:IsItemDataCached() then
        resultItem:ContinueOnItemLoad(function() end)
        return true
    end

    local text = AP.StatScan.ReadItemText(link)
    if not text then return true end

    -- Match by plain substring: structured stat parsing silently dropped suffix-gear and equip-effect matches.
    if next(active.stats) then
        if active.logic == "OR" then
            local matched = false
            for key in pairs(active.stats) do
                if text:find(STAT_TOKENS[key], 1, true) then
                    matched = true
                    break
                end
            end
            if not matched then return false end
        else
            for key in pairs(active.stats) do
                if not text:find(STAT_TOKENS[key], 1, true) then return false end
            end
        end
    end

    if active.dpsMin then
        local dps = AP.StatScan.ParseDPS(text)
        if not dps or dps < active.dpsMin then return false end
    end

    return true
end

-- Hook the mixin table now so Mixin() copies the wrapped OnLoad onto the dialog when it is created on AH open.
hooksecurefunc(AuctionatorShoppingItemMixin, "OnLoad", function(self)
    if self ~= _G.AuctionatorShoppingTabItemFrame then return end
    buildPanel(self)
end)

-- Replace rather than post-hook: a failed stat/DPS check must veto the result.
local originalCheckFilters = Auctionator.Search.CheckFilters
Auctionator.Search.CheckFilters = function(resultWithKey, filters)
    if not originalCheckFilters(resultWithKey, filters) then return false end
    return AP.ShoppingFilter.PassesFilter(resultWithKey)
end

-- Warm the suffix-variant cache as scan pages arrive so PassesFilter sees full stat lines when AddFinalResults fires.
hooksecurefunc(AuctionatorDirectSearchProviderMixin, "ProcessSearchResults", function(_, pageResults)
    if type(pageResults) ~= "table" then return end
    for _, entry in ipairs(pageResults) do
        local link = entry.itemLink
        if link then
            local entryItem = Item:CreateFromItemLink(link)
            if entryItem and not entryItem:IsItemEmpty() and not entryItem:IsItemDataCached() then
                entryItem:ContinueOnItemLoad(function() end)
            end
        end
    end
end)

-- Override, not hooksecurefunc: the draft must be captured BEFORE OnFinishedClicked hides the dialog (which clears the boxes via OnHide), and disarmed afterward if the click launched no search.
local originalOnFinished = AuctionatorShoppingItemMixin.OnFinishedClicked
function AuctionatorShoppingItemMixin.OnFinishedClicked(self, ...)
    if self ~= _G.AuctionatorShoppingTabItemFrame then
        return originalOnFinished(self, ...)
    end
    local panel = self.auctionatorPlusStatFilter
    if panel then
        local draft = readDraft(panel)
        pending = draft.any and draft or nil
    end
    originalOnFinished(self, ...)
    -- A launched search fires SearchStart synchronously above and consumes `pending`; if it survives, this finish was an edit/cancel with no search, so drop it.
    pending = nil
end

-- Consume the advanced-search draft; a normal search leaves `pending` nil and runs unfiltered.
AP.Bridge.Listen({ Auctionator.Shopping.Tab.Events.SearchStart }, function()
    active = pending
    pending = nil
end)
