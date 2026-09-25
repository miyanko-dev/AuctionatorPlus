local _, AP = ...

-- "Show Similar Items / Bags", shared half: what counts as comparable to the sale item, and the checkbox that turns it on. Each client's half finds the comparable auctions and merges them into its own current-prices listing
AP.SimilarItems = {}

-- Trade goods and unequippable items report an empty equipLoc
local NON_GEAR_SLOTS = {
    [""] = true,
    INVTYPE_BAG = true,
    INVTYPE_QUIVER = true,
    INVTYPE_AMMO = true,
    INVTYPE_NON_EQUIP = true,
    INVTYPE_NON_EQUIP_IGNORE = true,
}

-- Robes share the chest slot and main- or off-hand-only weapons the generic one-hand slot
local function normalizeSlot(equipLoc)
    if equipLoc == "INVTYPE_ROBE" then return "INVTYPE_CHEST" end
    if equipLoc == "INVTYPE_WEAPONMAINHAND" or equipLoc == "INVTYPE_WEAPONOFFHAND" then
        return "INVTYPE_WEAPON"
    end
    return equipLoc
end

-- Auction browse inventory types per equip location; slots absent here filter by subclass alone
local SLOT_INVENTORY_TYPES = {
    INVTYPE_HEAD = Enum.InventoryType.IndexHeadType,
    INVTYPE_NECK = Enum.InventoryType.IndexNeckType,
    INVTYPE_SHOULDER = Enum.InventoryType.IndexShoulderType,
    INVTYPE_BODY = Enum.InventoryType.IndexBodyType,
    INVTYPE_WAIST = Enum.InventoryType.IndexWaistType,
    INVTYPE_LEGS = Enum.InventoryType.IndexLegsType,
    INVTYPE_FEET = Enum.InventoryType.IndexFeetType,
    INVTYPE_WRIST = Enum.InventoryType.IndexWristType,
    INVTYPE_HAND = Enum.InventoryType.IndexHandType,
    INVTYPE_FINGER = Enum.InventoryType.IndexFingerType,
    INVTYPE_TRINKET = Enum.InventoryType.IndexTrinketType,
    INVTYPE_CLOAK = Enum.InventoryType.IndexCloakType,
    INVTYPE_HOLDABLE = Enum.InventoryType.IndexHoldableType,
}

local CHECKBOX_TEXT = {
    gear = {
        label = "Show Similar Items",
        tooltip = "When a piece of gear is placed for sale, also list the cheapest auction of every item with the same slot and armor or weapon type within %d levels of its required level. Matches must carry every stat of the item being sold, each within %d%% of its amount, with a stat count within %d of it. Weapons must additionally deal within %d%% of its damage per second. Click a similar auction to take its unit price for your listing.",
    },
    bag = {
        label = "Show Similar Bags",
        tooltip = "When a container is placed for sale, also list the cheapest auction of every container with the same number of slots. Click a similar auction to take its unit price for your listing.",
    },
}

-- Gear and bags remember their own choice
local SETTING_KEYS = { gear = "showSimilarItems", bag = "showSimilarBags" }

-- The checkbox and the sale-item kind it currently speaks for
local similarCheck, shownKind

-- ===== Sale item =====
-- Containers and quivers count as bags, everything equippable as gear
function AP.SimilarItems.KindOf(itemLink)
    local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(itemLink)
    if classID == Enum.ItemClass.Container or classID == Enum.ItemClass.Quiver then
        return "bag"
    end
    if type(equipLoc) == "string" and not NON_GEAR_SLOTS[equipLoc] then
        return "gear"
    end
    return nil
end

-- Whether the player wants comparables for this kind of sale item
function AP.SimilarItems.IsWanted(kind)
    return kind ~= nil and AP.DB()[SETTING_KEYS[kind]] == true
end

-- Server browse filters from class, subclass and slot; chest and robe listings form one pool like the normalized slot
local function categoryFilters(classID, subClassID, equipLoc)
    if classID ~= Enum.ItemClass.Armor then
        return { { classID = classID, subClassID = subClassID } }
    end
    if equipLoc == "INVTYPE_CHEST" or equipLoc == "INVTYPE_ROBE" then
        return {
            { classID = classID, subClassID = subClassID, inventoryType = Enum.InventoryType.IndexChestType },
            { classID = classID, subClassID = subClassID, inventoryType = Enum.InventoryType.IndexRobeType },
        }
    end
    return { { classID = classID, subClassID = subClassID, inventoryType = SLOT_INVENTORY_TYPES[equipLoc] } }
end

-- Comparison profile of the sale item, synchronous since the slotted item sits in the bags and is cached; nil for unsupported or uncached items
function AP.SimilarItems.ProfileFor(itemLink)
    local kind = AP.SimilarItems.KindOf(itemLink)
    local itemID, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemLink)
    local itemText = AP.ItemStats.Text(itemLink)
    if not kind or not itemID or not itemText then return nil end

    if kind == "bag" then
        local slotCount = AP.ItemStats.ParseSlotCount(itemText)
        if not slotCount then return nil end
        return {
            kind = "bag",
            itemID = itemID,
            itemLink = itemLink,
            slotCount = slotCount,
            filters = { { classID = classID } },
        }
    end

    return {
        kind = "gear",
        itemID = itemID,
        itemLink = itemLink,
        equipLoc = normalizeSlot(equipLoc),
        subClassID = subClassID,
        requiredLevel = AP.ItemStats.RequiredLevel(itemLink) or 0,
        filters = categoryFilters(classID, subClassID, equipLoc),

        -- Weapons gate on the DPS band before the stat set; a weapon with no parseable DPS line skips the gate
        dps = classID == Enum.ItemClass.Weapon and AP.ItemStats.ParseDPS(itemText) or nil,
        statSet = AP.ItemStats.FullStatSet(itemText),
    }
end

-- Required-level band for the server-side filter, only when the whole band sits above zero, since a level range drops "no level requirement" listings
function AP.SimilarItems.LevelRange(profile)
    local tolerance = AP.DB().levelTolerance
    local level = profile.requiredLevel
    if level and level > tolerance then
        return level - tolerance, level + tolerance
    end
    return nil, nil
end

-- ===== Matching =====
-- Instant check that needs no item data: same slot and armor or weapon type, or any container for a bag
function AP.SimilarItems.SameType(profile, itemRef)
    local _, _, _, equipLoc, _, classID, subClassID = AP.ItemStats.InstantInfo(itemRef)
    if profile.kind == "bag" then
        return classID == Enum.ItemClass.Container or classID == Enum.ItemClass.Quiver
    end
    return normalizeSlot(equipLoc) == profile.equipLoc and subClassID == profile.subClassID
end

-- Checks that need cached item data: required level, for weapons the DPS band, then every stat of the sale item within its value band with a stat count within the tolerance; bags must hold the same number of slots
function AP.SimilarItems.Matches(profile, itemRef)
    local itemText = AP.ItemStats.Text(itemRef)
    if not itemText then return false end

    if profile.kind == "bag" then
        return AP.ItemStats.ParseSlotCount(itemText) == profile.slotCount
    end

    local db = AP.DB()
    local level = AP.ItemStats.RequiredLevel(itemRef) or 0
    if math.abs(level - profile.requiredLevel) > db.levelTolerance then return false end

    if profile.dps then
        local dps = AP.ItemStats.ParseDPS(itemText)
        if not dps or math.abs(dps - profile.dps) > profile.dps * db.dpsTolerancePct / 100 then return false end
    end

    local stats = AP.ItemStats.FullStatSet(itemText)
    if not AP.ItemStats.Covers(stats, profile.statSet, db.statValueTolerance) then return false end
    return math.abs(AP.ItemStats.Count(stats) - AP.ItemStats.Count(profile.statSet)) <= db.statCountTolerance
end

-- ===== Checkbox =====
-- Label and saved state for the sale item's kind; nil hides the checkbox for items without comparables
function AP.SimilarItems.ShowCheckbox(kind)
    shownKind = kind
    if not similarCheck then return end

    local text = CHECKBOX_TEXT[kind]
    if not text then
        similarCheck:Hide()
        return
    end
    similarCheck.Text:SetText(text.label)
    similarCheck:SetChecked(AP.SimilarItems.IsWanted(kind))
    similarCheck:Show()
end

local function showTooltip(self)
    local text = CHECKBOX_TEXT[shownKind]
    if not text then return end
    local db = AP.DB()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, text.label)
    GameTooltip_AddHighlightLine(GameTooltip, text.tooltip:format(db.levelTolerance, db.statValueTolerance, db.statCountTolerance, db.dpsTolerancePct), true)
    GameTooltip:Show()
end

-- Created once per session and anchored by the caller; onToggle runs after the choice is saved, so the client's half can rebuild its listing
function AP.SimilarItems.CreateCheckbox(parent, onToggle)
    local check = CreateFrame("CheckButton", "AuctionatorPlusShowSimilar", parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetScript("OnClick", function(self)
        if not shownKind then return end
        local checked = self:GetChecked() and true or false
        AP.DB()[SETTING_KEYS[shownKind]] = checked
        onToggle(checked)
    end)
    check:SetScript("OnEnter", showTooltip)
    check:SetScript("OnLeave", GameTooltip_Hide)

    similarCheck = check
    AP.SimilarItems.ShowCheckbox(shownKind)
    return check
end
