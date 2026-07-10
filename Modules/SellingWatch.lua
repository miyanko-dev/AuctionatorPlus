local _, AP = ...

AP.SellingWatch = {}

-- Non-gear equip locations to ignore (trade goods / unequippable items report an
-- empty equipLoc). Every other equippable slot is supported.
local NON_GEAR_SLOTS = {
  [""] = true,
  INVTYPE_BAG = true,
  INVTYPE_QUIVER = true,
  INVTYPE_AMMO = true,
  INVTYPE_NON_EQUIP = true,
  INVTYPE_NON_EQUIP_IGNORE = true,
}

-- Body-armor slots carry an armor-type (cloth/leather/...) distinction; cloak,
-- neck, finger and trinket are wearable by all classes, so they are excluded.
local BODY_ARMOR_SLOTS = {
  INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true,
  INVTYPE_ROBE = true, INVTYPE_WAIST = true, INVTYPE_LEGS = true,
  INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
}

local LEVEL_RANGE = 2

-- A single placement fires StartFakeBuyLoading several times in a burst; absorb
-- repeats of the same item within this window, but re-run on a genuine re-drop.
local REDROP_DEBOUNCE = 1.0

local watch = {
  token = 0,          -- bumped per placement; supersedes in-flight work
  lastLink = nil,
  lastProcessAt = nil,
  pending = nil,      -- profile of the current sale item awaiting comparables
  scanning = false,
  scanEntries = nil,
  scanToken = nil,
  trackedLink = nil,  -- sale-slot item driving the checkbox state
  saleIsGear = false,
  saleHasStats = false,
}
local scanListener

local function IsSupportedGear(equipLoc)
  return type(equipLoc) == "string" and NON_GEAR_SLOTS[equipLoc] ~= true
end

-- The pair only acts on a supported piece of gear in the sale slot, and Same
-- Stats additionally needs the item to carry a primary stat; grey them out
-- otherwise (Same Stats also keeps requiring Check Similar Items to be on).
local function UpdateCheckboxState()
  local check, sameStats = AP.checkOtherItemsButton, AP.sameStatsButton
  if not check then return end

  if watch.saleIsGear then
    check:Enable()
    check.apLabel:SetFontObject("GameFontNormalSmall")
  else
    check:Disable()
    check.apLabel:SetFontObject("GameFontDisableSmall")
  end

  if watch.saleIsGear and watch.saleHasStats and AP.Settings.checkOtherItems then
    sameStats:Enable()
    sameStats.apLabel:SetFontObject("GameFontNormalSmall")
  else
    sameStats:Disable()
    sameStats.apLabel:SetFontObject("GameFontDisableSmall")
  end
end

-- Track what sits in the sale slot; equip location and stats are only readable
-- once the item data is cached, so the state settles in the load callback.
local function TrackSaleItem(itemLink)
  if itemLink == watch.trackedLink then return end
  watch.trackedLink = itemLink
  watch.saleIsGear = false
  watch.saleHasStats = false
  UpdateCheckboxState()

  local item = itemLink and Item:CreateFromItemLink(itemLink)
  if not item or item:IsItemEmpty() then return end
  item:ContinueOnItemLoad(function()
    if watch.trackedLink ~= itemLink then return end
    local equipLoc = AP.StatScan.GetEquipInfo(itemLink)
    watch.saleIsGear = IsSupportedGear(equipLoc)
    local statSet = AP.StatScan.PrimaryStatSet(AP.StatScan.ReadItemText(itemLink))
    watch.saleHasStats = next(statSet) ~= nil
    UpdateCheckboxState()
  end)
end

-- Weapons compare by weapon type only (restricted server-side via the category);
-- armor narrows by slot, plus armor type for the body slots.
local function BuildFilter(classID, equipLoc, itemSubType)
  if classID == Enum.ItemClass.Weapon then
    return nil
  end
  local filter = { equipLoc = equipLoc }
  if BODY_ARMOR_SLOTS[equipLoc] then
    filter.armorSubType = itemSubType
  end
  return filter
end

-- classID + Auctionator categoryKey for the item, slot-scoped for body armor
-- (e.g. "Armor/Mail/Hands"), otherwise class/subclass (e.g. "Weapon/Daggers").
local function CategoryForItem(itemLink, equipLoc)
  local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemLink)
  if not classID then return nil end
  local className = C_Item.GetItemClassInfo(classID)
  if not className then return nil end

  local subName = subClassID and C_Item.GetItemSubClassInfo(classID, subClassID)
  local categoryKey = className
  if subName and subName ~= "" then
    categoryKey = categoryKey .. "/" .. subName
  end
  if BODY_ARMOR_SLOTS[equipLoc] then
    local slotName = _G[equipLoc]
    if slotName and slotName ~= "" then
      local withSlot = categoryKey .. "/" .. slotName
      if Auctionator.Search.GetItemClassCategories(withSlot) then
        categoryKey = withSlot
      end
    end
  end
  return classID, categoryKey
end

-- Build the comparison profile for the dropped sale item (synchronous; the item
-- is cached once it is in the sell slot). nil for unsupported items.
local function ProfileForItem(itemLink)
  local equipLoc, _, itemSubType = AP.StatScan.GetEquipInfo(itemLink)
  if not IsSupportedGear(equipLoc) then return nil end

  local classID, categoryKey = CategoryForItem(itemLink, equipLoc)
  if not categoryKey then return nil end

  local requiredLevel = select(5, C_Item.GetItemInfo(itemLink)) or 0
  local minLevel, maxLevel
  if requiredLevel > 0 then
    minLevel = math.max(1, requiredLevel - LEVEL_RANGE)
    maxLevel = requiredLevel + LEVEL_RANGE
  end

  return {
    itemLink = itemLink,
    categoryKey = categoryKey,
    filter = BuildFilter(classID, equipLoc, itemSubType),
    minLevel = minLevel,
    maxLevel = maxLevel,
    statSet = AP.StatScan.PrimaryStatSet(AP.StatScan.ReadItemText(itemLink)),
  }
end

-- Candidate must sit in the same slot/armor type as the dropped item.
local function PassesFilter(itemLink, filter)
  if not filter then return true end
  local equipLoc, _, subType = AP.StatScan.GetEquipInfo(itemLink)
  if not equipLoc then return false end
  if filter.equipLoc and equipLoc ~= filter.equipLoc then return false end
  if filter.armorSubType and subType ~= filter.armorSubType then return false end
  return true
end

-- The selling tab's live current-prices data provider (name-based listing).
local function CurrentPricesProvider()
  local frame = _G.AuctionatorSellingFrame
  local buyFrame = frame and frame.BuyFrame
  local currentPrices = buyFrame and buyFrame.CurrentPrices
  return currentPrices and currentPrices.SearchDataProvider
end

local function ScanEvents()
  return { Auctionator.AH.Events.ScanResultsUpdate, Auctionator.AH.Events.ScanAborted }
end

local function StopScan()
  if watch.scanning then
    watch.scanning = false
    Auctionator.AH.AbortQuery()
    Auctionator.EventBus:Unregister(scanListener, ScanEvents())
  end
  watch.scanEntries = nil
end

-- Load every candidate's item data, then call back. Reading stat tooltips on
-- random-suffix gear needs the item cached, so wait before filtering by stats.
local function EnsureLoaded(entries, callback)
  local loading = {}
  for _, entry in ipairs(entries) do
    local item = entry.itemLink and Item:CreateFromItemLink(entry.itemLink)
    if item and not item:IsItemEmpty() and not item:IsItemDataCached() then
      table.insert(loading, item)
    end
  end
  local remaining = #loading
  if remaining == 0 then callback(); return end
  for _, item in ipairs(loading) do
    item:ContinueOnItemLoad(function()
      remaining = remaining - 1
      if remaining == 0 then callback() end
    end)
  end
end

-- Append the kept entries to the current-prices listing and repaint.
local function MergeIntoProvider(provider, entries)
  local added = 0
  for _, entry in ipairs(entries) do
    entry.page = 0
    entry.query = provider.query
    table.insert(provider.allAuctions, entry)
    added = added + 1
  end
  if added > 0 then provider:PopulateAuctions() end
end

-- Merge slot/armor/level matches into the current-prices listing alongside the
-- name-based results. With "Same Stats" on, narrow further to items carrying the
-- exact same primary-stat set as the dropped item (values ignored).
local function InjectComparables(pending, entries)
  local provider = CurrentPricesProvider()
  if not provider or not provider.allAuctions then return end

  local candidates = {}
  for _, entry in ipairs(entries) do
    local link = entry.itemLink
    if link
        and Auctionator.Search.GetCleanItemLink(link) ~= provider.searchKey
        and PassesFilter(link, pending.filter) then
      table.insert(candidates, entry)
    end
  end

  if not (AP.Settings.sameStats and pending.statSet) then
    MergeIntoProvider(provider, candidates)
    return
  end

  EnsureLoaded(candidates, function()
    if watch.pending ~= pending then return end
    local matches = {}
    for _, entry in ipairs(candidates) do
      local set = AP.StatScan.PrimaryStatSet(AP.StatScan.ReadItemText(entry.itemLink))
      if AP.StatScan.SameStatSet(set, pending.statSet) then
        table.insert(matches, entry)
      end
    end
    MergeIntoProvider(provider, matches)
  end)
end

-- Background search for same slot/armor type within +/- LEVEL_RANGE of the
-- required level. Runs on the shared scanner without switching tabs; safe to
-- start here because the selling tab's own name search has just finished.
local function RunComparableSearch(pending)
  watch.scanEntries = {}
  watch.scanning = true
  watch.scanToken = pending.token
  Auctionator.EventBus:Register(scanListener, ScanEvents())

  local ok = pcall(Auctionator.AH.QueryAuctionItems, {
    searchString = "",
    minLevel = pending.minLevel,
    maxLevel = pending.maxLevel,
    itemClassFilters = Auctionator.Search.GetItemClassCategories(pending.categoryKey) or {},
    isExact = false,
  })
  if not ok then StopScan() end
end

local function CommitPending(itemLink)
  watch.lastLink = itemLink
  watch.lastProcessAt = GetTime()

  local profile = ProfileForItem(itemLink)
  if not profile then
    watch.pending = nil
    return
  end
  profile.token = watch.token
  watch.pending = profile
end

-- A gear item entered the sale slot: capture its profile. The comparable search
-- is started once the selling tab's own name search completes (ViewSetup), so
-- the two don't fight over the shared scanner.
local function StartForItem(itemLink)
  watch.token = watch.token + 1
  StopScan()

  if C_Item.GetItemInfo(itemLink) then
    CommitPending(itemLink)
  else
    local token = watch.token
    local item = Item:CreateFromItemLink(itemLink)
    if item and not item:IsItemEmpty() then
      item:ContinueOnItemLoad(function()
        if token == watch.token then CommitPending(itemLink) end
      end)
    end
  end
end

local function ReceiveEvent(_, eventName, eventData, arg3)
  local Selling = Auctionator.Selling.Events
  local Buying = Auctionator.Buying.Events
  local AH = Auctionator.AH.Events

  if eventName == Selling.StartFakeBuyLoading then
    local link = eventData and eventData.itemLink
    if not link then return end
    TrackSaleItem(link)
    if not AP.Settings.checkOtherItems then return end
    -- Skip the rapid repeat fires for the item we just handled; a later re-drop
    -- still re-runs so the comparables stay up to date.
    if link == watch.lastLink and watch.lastProcessAt
        and (GetTime() - watch.lastProcessAt) < REDROP_DEBOUNCE then
      return
    end
    StartForItem(link)

  elseif eventName == Selling.ClearBagItem then
    watch.token = watch.token + 1
    watch.lastLink = nil
    watch.pending = nil
    TrackSaleItem(nil)
    StopScan()

  elseif eventName == Buying.ViewSetup then
    -- The selling tab's name search finished; the scanner is free for ours.
    local pending = watch.pending
    if pending and not pending.searchStarted then
      pending.searchStarted = true
      C_Timer.After(0, function()
        if watch.pending == pending then RunComparableSearch(pending) end
      end)
    end

  elseif eventName == AH.ScanResultsUpdate then
    if not watch.scanning then return end
    if type(eventData) == "table" then
      for _, entry in ipairs(eventData) do
        table.insert(watch.scanEntries, entry)
      end
    end
    if arg3 then -- gotAllResults
      local pending, collected, token = watch.pending, watch.scanEntries, watch.scanToken
      watch.scanning = false
      Auctionator.EventBus:Unregister(scanListener, ScanEvents())
      watch.scanEntries = nil
      if pending and pending.token == token then
        InjectComparables(pending, collected)
      end
    end

  elseif eventName == AH.ScanAborted then
    if watch.scanning then
      watch.scanning = false
      Auctionator.EventBus:Unregister(scanListener, ScanEvents())
      watch.scanEntries = nil
    end
  end
end

scanListener = AP.Bridge.Listen({
  Auctionator.Selling.Events.StartFakeBuyLoading,
  Auctionator.Selling.Events.ClearBagItem,
  Auctionator.Buying.Events.ViewSetup,
}, ReceiveEvent)

local function EnsureCheckbox()
  if AP.checkOtherItemsButton then return true end
  local sellingFrame = _G.AuctionatorSellingFrame
  local anchor = sellingFrame and (sellingFrame.BagInset or sellingFrame)
  if not sellingFrame or not anchor then return false end

  -- Two stacked rows must fit the ~37px strip between the sale-item frame and
  -- the bag inset, so these boxes are compact (18px) rather than the usual 24.
  -- This pair forms the right column, top-aligned beside the Use TSM Trend box
  -- (left column) when that feature is present; TSMTrend.lua re-anchors it if
  -- it creates its box after this one.
  local check = CreateFrame(
    "CheckButton", "AuctionatorPlusCheckSimilarItems", sellingFrame, "UICheckButtonTemplate")
  check:SetSize(18, 18)
  if AP.tsmTrendSellingLabel then
    check:SetPoint("LEFT", AP.tsmTrendSellingLabel, "RIGHT", 12, 0)
  else
    check:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 4, 20)
  end
  check:SetChecked(AP.Settings.checkOtherItems)

  local label = check:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("LEFT", check, "RIGHT", 2, 0)
  label:SetText("Check Similar Items")

  -- "Same Stats" narrows the similar-items list to the same primary-stat set.
  -- Only meaningful while similar items are shown, so it tracks the box above.
  local sameStats = CreateFrame(
    "CheckButton", "AuctionatorPlusSameStats", sellingFrame, "UICheckButtonTemplate")
  sameStats:SetSize(18, 18)
  sameStats:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 0, 0)
  sameStats:SetChecked(AP.Settings.sameStats)

  local sameStatsLabel = sameStats:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  sameStatsLabel:SetPoint("LEFT", sameStats, "RIGHT", 2, 0)
  sameStatsLabel:SetText("Same Stats")

  check.apLabel = label
  sameStats.apLabel = sameStatsLabel

  check:SetScript("OnClick", function(self)
    AP.Settings.checkOtherItems = self:GetChecked() and true or false
    AP.SaveSettings()
    UpdateCheckboxState()
  end)
  check:SetMotionScriptsWhileDisabled(true)
  check:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Check Similar Items")
    GameTooltip:AddLine(
      "When a gear item is placed for sale, also list other auctions of the same slot, armor type, and required level (+/-2) in the current prices panel.",
      1, 1, 1, true)
    if not watch.saleIsGear then
      GameTooltip:AddLine("Enabled while a piece of gear sits in the sale slot.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
  end)
  check:SetScript("OnLeave", GameTooltip_Hide)

  sameStats:SetScript("OnClick", function(self)
    AP.Settings.sameStats = self:GetChecked() and true or false
    AP.SaveSettings()
  end)
  sameStats:SetMotionScriptsWhileDisabled(true)
  sameStats:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Same Stats")
    GameTooltip:AddLine(
      "Only list similar items that carry the same stats as the item being sold (e.g. Agility and Stamina). Stat values are ignored.",
      1, 1, 1, true)
    if not (watch.saleIsGear and watch.saleHasStats) then
      GameTooltip:AddLine("Enabled while gear with primary stats sits in the sale slot, with Check Similar Items on.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
  end)
  sameStats:SetScript("OnLeave", GameTooltip_Hide)

  AP.checkOtherItemsButton = check
  AP.sameStatsButton = sameStats

  UpdateCheckboxState()

  return true
end

local function HookRefreshButton()
  if AP.refreshButtonHooked then return true end
  local sellingFrame = _G.AuctionatorSellingFrame
  local buyFrame = sellingFrame and sellingFrame.BuyFrame
  local currentPrices = buyFrame and buyFrame.CurrentPrices
  local refreshButton = currentPrices and currentPrices.RefreshButton
  if not refreshButton then return false end

  -- Refresh clears the data provider's auctions and re-runs the name search;
  -- clearing searchStarted lets the next ViewSetup re-trigger our comparable
  -- scan so the merged results stay in sync.
  refreshButton:HookScript("OnClick", function()
    if not watch.pending then return end
    StopScan()
    watch.pending.searchStarted = false
  end)

  AP.refreshButtonHooked = true
  return true
end

function AP.SellingWatch.Ensure()
  local checkboxOk = EnsureCheckbox()
  local refreshOk = HookRefreshButton()
  return checkboxOk and refreshOk
end
