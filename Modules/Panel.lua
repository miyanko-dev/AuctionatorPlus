local _, ns = ...

-- Shared dialog for this author's addons: each client's own dialog border, header banner and close button, with Blizzard font objects for all text
local Panel = {}
ns.Panel = Panel

-- Content insets; the first element clears the header banner, whose art ends about 28px below the top edge on both clients
Panel.INSET = 24
Panel.PAD_TOP = 40
Panel.SECTION = 16
Panel.GAP = 8
Panel.ROW = 24
Panel.BUTTON_HEIGHT = 22

-- Era's dialogs carry the UI-DialogBox backdrop of its GameMenuFrame on the frame itself, as GuildInfoFrame does, so the frame's own text draws above it
local function classicFrame(name, parent)
    local panel = CreateFrame("Frame", name, parent, "BackdropTemplate")
    panel:SetBackdrop(BACKDROP_DIALOG_32_32)
    return panel
end

-- Forever's dialogs use the DiamondMetal border of its GameMenuFrame, which shares the frame's level so the frame's own text draws above its background
local function modernFrame(name, parent)
    local panel = CreateFrame("Frame", name, parent)
    local border = CreateFrame("Frame", nil, panel, "DialogBorderTemplate")
    border:SetAllPoints(panel)
    return panel
end

-- ClassicDialogHeaderTemplate loads only for the classic family, so its presence picks Era's art; close offsets follow Blizzard's own dialogs on each client
local SKIN = C_XMLUtil.GetTemplateInfo("ClassicDialogHeaderTemplate")
    and { create = classicFrame, header = "ClassicDialogHeaderTemplate", closeX = -3, closeY = -3 }
    or { create = modernFrame, header = "DialogHeaderTemplate", closeX = -2, closeY = -2 }

-- Movable dialog on the DIALOG strata that closes on Escape; starts hidden
function Panel.Create(name, title, width, parent)
    local panel = SKIN.create(name, parent or UIParent)
    panel:SetSize(width, Panel.PAD_TOP)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    tinsert(UISpecialFrames, name)

    -- Setup sizes the banner to the title in the header's default GameFontNormal
    local header = CreateFrame("Frame", nil, panel, SKIN.header)
    header:Setup(title)

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", SKIN.closeX, SKIN.closeY)

    panel.contentHeight = 0
    panel:Hide()
    return panel
end

-- Next free spot in the content column, gap below the previous element
local function stack(panel, region, gap)
    if panel.lastRegion then
        region:SetPoint("TOPLEFT", panel.lastRegion, "BOTTOMLEFT", 0, -gap)
        panel.contentHeight = panel.contentHeight + gap
    else
        region:SetPoint("TOPLEFT", panel, "TOPLEFT", Panel.INSET, -Panel.PAD_TOP)
    end
    panel.lastRegion = region
end

-- Wrapped text across the content width in a Blizzard font object; the explicit width lets the height be measured before the first layout pass
function Panel.AddText(panel, fontObject, text, gap)
    local fontString = panel:CreateFontString(nil, "OVERLAY", fontObject)
    fontString:SetWidth(panel:GetWidth() - 2 * Panel.INSET)
    fontString:SetJustifyH("LEFT")
    fontString:SetWordWrap(true)
    fontString:SetText(text)
    stack(panel, fontString, gap or Panel.SECTION)
    panel.contentHeight = panel.contentHeight + math.ceil(fontString:GetStringHeight())
    return fontString
end

-- Gold heading over white body text
function Panel.AddSection(panel, heading, body)
    Panel.AddText(panel, "GameFontNormal", heading)
    Panel.AddText(panel, "GameFontHighlight", body, Panel.GAP)
end

-- Full-width button a section gap below the previous element
function Panel.AddButton(panel, text, onClick)
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(panel:GetWidth() - 2 * Panel.INSET, Panel.BUTTON_HEIGHT)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    stack(panel, button, Panel.SECTION)
    panel.contentHeight = panel.contentHeight + Panel.BUTTON_HEIGHT
    return button
end

-- Height from the header clearance to the last element plus the bottom inset
function Panel.Fit(panel)
    panel:SetHeight(Panel.PAD_TOP + panel.contentHeight + Panel.INSET)
end
