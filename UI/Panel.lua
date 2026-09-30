local _, ns = ...

-- Shared native UI pieces: GameMenuFrame-style dialogs with Blizzard font objects for all text, and the fixed-size buttons this addon adds to Auctionator's tabs
local Panel = {}
ns.Panel = Panel

-- Content starts below the header banner, whose art ends about 28px below the top edge; side and bottom padding match
Panel.INSET = 20
Panel.PAD_TOP = 40
Panel.SECTION = 16
Panel.GAP = 8
Panel.ROW = 24
Panel.BUTTON_HEIGHT = 22

-- Width of the tab buttons, fixed so a changing progress label never shifts the buttons anchored beside them
local TAB_BUTTON_WIDTH = 110

-- Movable dialog on the DIALOG strata that closes on Escape; starts hidden. The DiamondMetal border shares the frame's level, so the frame's own text draws above its background
function Panel.Create(name, title, width, parent)
    local panel = CreateFrame("Frame", name, parent or UIParent)
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

    panel.Border = CreateFrame("Frame", nil, panel, "DialogBorderTemplate")
    panel.Border:SetAllPoints(panel)

    -- Setup sizes the banner to the title in the header's default GameFontNormal
    panel.Header = CreateFrame("Frame", nil, panel, "DialogHeaderTemplate")
    panel.Header:Setup(title)

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)

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

-- Button for one of Auctionator's tabs in the height of Auctionator's own buttons, with a titled tooltip above it; addTooltipLines, when given, appends lines that depend on the moment
function Panel.CreateTabButton(name, parent, label, title, body, addTooltipLines)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetSize(TAB_BUTTON_WIDTH, Panel.BUTTON_HEIGHT)
    button:SetText(label)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip_SetTitle(GameTooltip, title)
        GameTooltip_AddHighlightLine(GameTooltip, body, true)
        if addTooltipLines then addTooltipLines(GameTooltip) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end
