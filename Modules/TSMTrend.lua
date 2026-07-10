local _, AP = ...

-- UI half of the TSM feed: an opt-in trend baseline swap (Auctionator scan
-- average vs TSM market value), a market-value tooltip line, and the two
-- checkboxes. Wraps AP functions from PriceHistory.lua instead of editing
-- them, so deleting this file and TSMFeed.lua fully revokes the feature.
AP.TSMTrend = {}

-- ===== Trend baseline swap =====

-- Set by AverageFor and consumed by the Colorize call that immediately follows
-- it inside a trend-cell update; marks cells that fell back to scan history
-- while the TSM baseline is active.
local usedScanFallback = false

local origAverageFor = AP.Trend.AverageFor
AP.Trend.AverageFor = function(itemLink)
  usedScanFallback = false
  if not (AP.TSMFeed.Settings.useTrend and AP.TSMFeed.HasData()) then
    return origAverageFor(itemLink)
  end

  local tsmValue = AP.TSMFeed.MarketValueForLink(itemLink)
  if tsmValue then
    return tsmValue
  end

  usedScanFallback = true
  return origAverageFor(itemLink)
end

local origColorize = AP.Trend.Colorize
AP.Trend.Colorize = function(pct, mode)
  local text = origColorize(pct, mode)
  if text and usedScanFallback then
    text = text .. GRAY_FONT_COLOR:WrapTextInColorCode("*")
  end
  usedScanFallback = false
  return text
end

-- ===== Tooltip line =====

local origApply = AP.Tooltip.Apply
AP.Tooltip.Apply = function(tooltip, itemLink)
  origApply(tooltip, itemLink)

  local value = AP.TSMFeed.MarketValueForLink(itemLink)
  if not value then return end

  local label = "TSM Market Value"
  local age = AP.TSMFeed.AgeText()
  if age then
    label = label .. " (" .. age .. ")"
  end
  tooltip:AddDoubleLine(label, WHITE_FONT_COLOR:WrapTextInColorCode(AP.Format.Money(value)))
  tooltip:Show()
end

-- ===== Checkboxes =====

local trendBoxes = {}

local function SetUseTrend(enabled)
  AP.TSMFeed.Settings.useTrend = enabled and true or false
  AP.TSMFeed.SaveSettings()
  for _, box in ipairs(trendBoxes) do
    box:SetChecked(AP.TSMFeed.Settings.useTrend)
  end
  if AP.RepaintTrendColumns then
    AP.RepaintTrendColumns()
  end
end

local function TrendTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText("Use TSM Trend")
  local age = AP.TSMFeed.AgeText()
  GameTooltip:AddLine(
    "Base the Trend column and tooltip trend on the TSM app's market value instead of your own scan history."
    .. " Cells marked with * had no TSM value and fall back to scan history.",
    1, 1, 1, true)
  if age then
    GameTooltip:AddLine("TSM data age: " .. age, 0.7, 0.7, 0.7)
  elseif not AP.TSMFeed.HasData() then
    GameTooltip:AddLine("No TSM data found. Is the TSM desktop app running?", 1, 0.4, 0.4)
  end
  GameTooltip:Show()
end

local function CreateTrendBox(name, parent)
  local box = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
  box:SetSize(24, 24)
  box:SetChecked(AP.TSMFeed.Settings.useTrend)
  box:SetScript("OnClick", function(self) SetUseTrend(self:GetChecked()) end)
  box:SetScript("OnEnter", TrendTooltip)
  box:SetScript("OnLeave", GameTooltip_Hide)

  local label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("LEFT", box, "RIGHT", 2, 0)
  label:SetText("Use TSM Trend")

  -- No AppData captured this session (app not running or AppHelper missing):
  -- grey the toggle out but keep the tooltip, which explains what is wrong.
  if not AP.TSMFeed.HasData() then
    box:Disable()
    box:SetMotionScriptsWhileDisabled(true)
    label:SetFontObject("GameFontDisableSmall")
  end

  table.insert(trendBoxes, box)
  return box, label
end

-- The import checkbox lives once, in the shopping tab, next to the trend box.
local function CreateImportBox(parent, anchorLabel)
  local box = CreateFrame(
    "CheckButton", "AuctionatorPlusTSMImport", parent, "UICheckButtonTemplate")
  box:SetSize(24, 24)
  box:SetPoint("LEFT", anchorLabel, "RIGHT", 12, 0)
  box:SetChecked(AP.TSMFeed.Settings.importScans)

  local label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("LEFT", box, "RIGHT", 2, 0)
  label:SetText("Import TSM Scans")

  box:SetScript("OnClick", function(self)
    AP.TSMFeed.Settings.importScans = self:GetChecked() and true or false
    AP.TSMFeed.SaveSettings()
    if AP.TSMFeed.Settings.importScans then
      local count = AP.TSMFeed.ImportScanData()
      if count then
        print(string.format(
          "|cff88ccffAuctionatorPlus|r: merged %d TSM prices into the scan database (%s old).",
          count, AP.TSMFeed.AgeText() or "?"))
      end
    end
  end)
  box:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Import TSM Scans")
    GameTooltip:AddLine(
      "On login, merge the TSM app's current lowest-buyout snapshot into Auctionator's price"
      .. " database, like a full scan taken when the app last synced. Existing history is kept.",
      1, 1, 1, true)
    GameTooltip:Show()
  end)
  box:SetScript("OnLeave", GameTooltip_Hide)

  return box
end

-- Shopping tab: both checkboxes sit in the bottom row, right of the Full Scan
-- button (created by FullScanButton.lua, so wait for it).
local function EnsureShoppingBoxes()
  if AP.tsmTrendShoppingBox then return true end
  local shoppingFrame = _G.AuctionatorShoppingFrame
  local fullScanButton = AP.fullScanShoppingButton
  if not shoppingFrame or not fullScanButton then return false end

  local box, label = CreateTrendBox("AuctionatorPlusTSMTrendShopping", shoppingFrame)
  box:SetPoint("LEFT", fullScanButton, "RIGHT", 8, 0)
  CreateImportBox(shoppingFrame, label)

  AP.tsmTrendShoppingBox = box
  return true
end

-- Selling tab: left column above the bag inset, on the same top line as the
-- Check Similar Items box; that box and Same Stats form the right column.
local function EnsureSellingBox()
  if AP.tsmTrendSellingBox then return true end
  local sellingFrame = _G.AuctionatorSellingFrame
  local anchor = sellingFrame and (sellingFrame.BagInset or sellingFrame)
  if not sellingFrame then return false end

  local box, label = CreateTrendBox("AuctionatorPlusTSMTrendSelling", sellingFrame)
  box:SetSize(18, 18)
  box:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 4, 20)

  AP.tsmTrendSellingBox = box
  AP.tsmTrendSellingLabel = label

  -- If SellingWatch built its column first, move it beside this one (Same
  -- Stats follows automatically, it hangs off the Similar Items box).
  if AP.checkOtherItemsButton then
    AP.checkOtherItemsButton:ClearAllPoints()
    AP.checkOtherItemsButton:SetPoint("LEFT", label, "RIGHT", 12, 0)
  end

  return true
end

-- The Auctionator frames appear on (or shortly after) the first auction-house
-- open; retry like Bootstrap does for the other buttons.
local function EnsureBoxes(attempt)
  attempt = attempt or 1
  local shoppingReady = EnsureShoppingBoxes()
  local sellingReady = EnsureSellingBox()
  if (shoppingReady and sellingReady) or attempt > 20 then return end
  C_Timer.After(0.5, function() EnsureBoxes(attempt + 1) end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:SetScript("OnEvent", function() EnsureBoxes() end)
