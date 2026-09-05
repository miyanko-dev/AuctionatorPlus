local _, AP = ...

-- Options page under Options > AddOns, plus the button that opens it from Auctionator's own tab
AP.SettingsPanel = {}

local function plusPercent(value) return ("+%d%%"):format(value) end
local function bandPercent(value) return ("±%d%%"):format(value) end

local function levels(value) return ("±%d levels"):format(value) end
local function plusMinus(value) return ("±%d"):format(value) end
local function percentOff(value) return value == 0 and "Off" or ("%d%%"):format(value) end

-- Sections in display order; a control is key, label, tooltip, then min, max, step, value formatter for sliders or checkbox = true
local SECTIONS = {
    { "Bag glow", {
        { "sellThresholdPct", "Sell threshold", "Bag items glow green once a Relative Value reaches this.", 5, 100, 1, plusPercent },
        { "glowRequireBoth", "Require both values", "Checked: both the Auctionator and the TSM Relative Value must reach the threshold, where TSM has data. Unchecked: one is enough.", checkbox = true },
        { "minSaleRate", "Minimum sale rate", "Bag items whose TSM sale rate (share of posted auctions that sell, region-wide) sits under this never glow. Off skips the check.", 0, 100, 5, percentOff },
    } },
    { "Similar items", {
        { "levelTolerance", "Level range", "Comparable gear may require a level this far above or below the sale item.", 0, 10, 1, levels },
        { "dpsTolerancePct", "Weapon DPS range", "Comparable weapons must deal damage per second within this share of the sale item's.", 0, 50, 5, bandPercent },
        { "statValueTolerance", "Stat value range", "Each stat of comparable gear must sit within this share of the sale item's amount.", 0, 100, 5, bandPercent },
        { "statCountTolerance", "Stat count range", "Comparable gear must carry every stat of the sale item; its total stat count may differ by this many.", 0, 5, 1, plusMinus },
    } },
}

local category

local function addControl(db, def)
    local key, label, tooltip, minValue, maxValue, step, formatter = unpack(def)
    local varType = def.checkbox and Settings.VarType.Boolean or Settings.VarType.Number
    local setting = Settings.RegisterAddOnSetting(category, "AUCTIONATORPLUS_" .. key:upper(), key, db, varType, label, AP.Defaults[key])

    -- Painted glows depend on the threshold and the both-values rule
    setting:SetValueChangedCallback(AP.BagGlow.Repaint)
    if def.checkbox then
        Settings.CreateCheckbox(category, setting, tooltip)
        return
    end
    local options = Settings.CreateSliderOptions(minValue, maxValue, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
    Settings.CreateSlider(category, setting, options, tooltip)
end

function AP.SettingsPanel.Register()
    local db = AP.DB()

    -- The login toggle used to be the TSM hint; carry the saved choice over
    if db.tsmHint ~= nil then
        db.guideAtLogin, db.tsmHint = db.tsmHint, nil
    end

    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("Auctionator Plus")

    for _, section in ipairs(SECTIONS) do
        local title, controls = unpack(section)
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title))
        for _, def in ipairs(controls) do addControl(db, def) end
    end

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("General"))
    local guideAtLogin = Settings.RegisterAddOnSetting(category, "AUCTIONATORPLUS_GUIDEATLOGIN", "guideAtLogin", db, Settings.VarType.Boolean, "Guide at login", AP.Defaults.guideAtLogin)
    Settings.CreateCheckbox(category, guideAtLogin, "Show the Auctionator Plus guide once per character at login.")
    layout:AddInitializer(CreateSettingsButtonInitializer("Guide", "Open", AP.Guide.Show, "What Auctionator Plus adds and how to enable the TSM features.", true))

    Settings.RegisterAddOnCategory(category)
end

function AP.SettingsPanel.Open()
    Settings.OpenToCategory(category:GetID())
end

-- Sits left of Auctionator's own "Open Addon Options" button on its tab; that tab frame exists once the AH has opened
function AP.SettingsPanel.EnsureButton()
    if AP.optionsButton then return true end
    local configTab = _G.AuctionatorConfigFrame
    if not configTab or not configTab.OptionsButton then return false end

    local button = CreateFrame("Button", "AuctionatorPlusOptionsButton", configTab, "UIPanelDynamicResizeButtonTemplate")
    button:SetText("Auctionator Plus Options")
    DynamicResizeButton_Resize(button)
    button:SetPoint("TOPRIGHT", configTab.OptionsButton, "TOPLEFT", -3, 0)
    button:SetScript("OnClick", AP.SettingsPanel.Open)
    AP.optionsButton = button
    return true
end
