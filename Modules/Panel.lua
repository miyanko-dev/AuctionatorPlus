local _, AP = ...

-- Shared dialog look for every Auctionator Plus panel: AceGUI-style backdrop, header banner and corner close, the same design as the Target Finder panel
AP.Panel = {}

AP.Panel.PAD = 16
AP.Panel.SECTION_GAP = 16
AP.Panel.TEXT_GAP = 4
AP.Panel.BUTTON_HEIGHT = 22

-- Clears the header banner
AP.Panel.PAD_TOP = 48

local HEADER_TEXTURE = "Interface\\DialogFrame\\UI-DialogBox-Header"

-- Banner rebuilt from three texture pieces (left cap, repeating middle, right cap) with the texCoords AceGUI uses
local function addTitleBanner(panel, text)
    local mid = panel:CreateTexture(nil, "OVERLAY")
    mid:SetTexture(HEADER_TEXTURE)
    mid:SetTexCoord(0.31, 0.67, 0, 0.63)
    mid:SetPoint("TOP", panel, "TOP", 0, 12)
    mid:SetHeight(40)

    local left = panel:CreateTexture(nil, "OVERLAY")
    left:SetTexture(HEADER_TEXTURE)
    left:SetTexCoord(0.21, 0.31, 0, 0.63)
    left:SetPoint("RIGHT", mid, "LEFT")
    left:SetSize(30, 40)

    local right = panel:CreateTexture(nil, "OVERLAY")
    right:SetTexture(HEADER_TEXTURE)
    right:SetTexCoord(0.67, 0.77, 0, 0.63)
    right:SetPoint("LEFT", mid, "RIGHT")
    right:SetSize(30, 40)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", mid, "TOP", 0, -14)
    title:SetText(text)
    mid:SetWidth((title:GetStringWidth() or 0) + 10)
end

-- Movable dialog on the DIALOG strata that closes on Escape; starts hidden
function AP.Panel.Create(name, title, width, parent)
    local panel = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
    panel:SetSize(width, 1)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    tinsert(UISpecialFrames, name)
    addTitleBanner(panel, title)

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)

    panel.contentHeight = 0
    panel:Hide()
    return panel
end

-- Gold heading with wrapped body text, stacked under the previous section; the content height feeds Fit
function AP.Panel.AddSection(panel, heading, body)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if panel.lastRegion then
        title:SetPoint("TOPLEFT", panel.lastRegion, "BOTTOMLEFT", 0, -AP.Panel.SECTION_GAP)
        panel.contentHeight = panel.contentHeight + AP.Panel.SECTION_GAP
    else
        title:SetPoint("TOPLEFT", panel, "TOPLEFT", AP.Panel.PAD, -AP.Panel.PAD_TOP)
    end
    title:SetText(heading)

    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -AP.Panel.TEXT_GAP)
    text:SetPoint("RIGHT", panel, "RIGHT", -AP.Panel.PAD, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    text:SetText(body)

    panel.contentHeight = panel.contentHeight + math.ceil(title:GetStringHeight()) + AP.Panel.TEXT_GAP + math.ceil(text:GetStringHeight())
    panel.lastRegion = text
end

-- Full-width button under the previous section, the way Target Finder ends its panel
function AP.Panel.AddButton(panel, text, onClick)
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetHeight(AP.Panel.BUTTON_HEIGHT)
    button:SetPoint("TOPLEFT", panel.lastRegion, "BOTTOMLEFT", 0, -AP.Panel.SECTION_GAP)
    button:SetPoint("RIGHT", panel, "RIGHT", -AP.Panel.PAD, 0)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    panel.contentHeight = panel.contentHeight + AP.Panel.SECTION_GAP + AP.Panel.BUTTON_HEIGHT
    panel.lastRegion = button
    return button
end

-- Height from the banner padding to the last section plus bottom padding
function AP.Panel.Fit(panel)
    panel:SetHeight(AP.Panel.PAD_TOP + panel.contentHeight + AP.Panel.PAD)
end
