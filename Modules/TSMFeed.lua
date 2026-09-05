local _, AP = ...

-- Capture the TSM desktop app's market data: AppData.lua calls the global TSM_APPHELPER_LOAD_DATA while addons load, so wrap it (forwarding to TSM untouched) and decode the payloads for this realm and region
AP.TSMFeed = {}

local DATA_TAG = "AUCTIONDB_NON_COMMODITY_DATA"
local STAT_TAG = "AUCTIONDB_NON_COMMODITY_SCAN_STAT"
local SALE_TAG = "AUCTIONDB_REGION_SALE"

-- Raw payload strings per tag
local captured = {}

-- Per dbKey: marketValue is the realm's 14-day smoothed value in copper, salePercent the region-wide share of posted auctions that sell; downloadTime is when the app downloaded the snapshot
local feed = {
    marketValue = nil,
    salePercent = nil,
    downloadTime = nil,
}

-- ===== Payload capture =====
-- Match keys the way AppHelper does: case-insensitive, curly apostrophes squashed
local function sameKey(a, b)
    a = string.gsub(a, "\226", "'")
    b = string.gsub(b, "\226", "'")
    return string.lower(a) == string.lower(b)
end

local REGION_NAMES = { "US", "KR", "EU", "TW", "CN" }

-- The app files region data per era flavor: SoD- for Season of Discovery, HC- for hardcore, Classic- for everything else, anniversary realms included
local function regionKey()
    local prefix = "Classic"
    local sodID = Enum.SeasonID and Enum.SeasonID.SeasonOfDiscovery
    if sodID and C_Seasons and C_Seasons.HasActiveSeason() and C_Seasons.GetActiveSeason() == sodID then
        prefix = "SoD"
    elseif C_GameRules and C_GameRules.IsHardcoreActive() then
        prefix = "HC"
    end
    return prefix .. "-" .. (REGION_NAMES[GetCurrentRegion()] or "")
end

-- Realm payloads carry a -Faction suffix on era; the sale payload is keyed by region
local function wanted(tag, realmOrRegion)
    if tag == SALE_TAG then
        return sameKey(realmOrRegion, regionKey())
    end
    if tag == DATA_TAG or tag == STAT_TAG then
        return sameKey(realmOrRegion, GetRealmName() .. "-" .. UnitFactionGroup("player"))
    end
    return false
end

local function capture(tag, realmOrRegion, payload)
    if type(tag) ~= "string" or type(realmOrRegion) ~= "string" or type(payload) ~= "string" then
        return
    end
    if wanted(tag, realmOrRegion) then
        captured[tag] = payload
    end
end

-- Re-wrap the global on every ADDON_LOADED until AppHelper has delivered: TSM installs its own handler while loading (after this addon, alphabetically)
local installedHook

local function installHook()
    local current = TSM_APPHELPER_LOAD_DATA
    if current ~= nil and current == installedHook then return end
    local forward = current
    installedHook = function(tag, realmOrRegion, payload)
        capture(tag, realmOrRegion, payload)
        if forward then forward(tag, realmOrRegion, payload) end
    end
    TSM_APPHELPER_LOAD_DATA = installedHook
end

installHook()

-- ===== Payload decoding (format as parsed by TSM's AuctionDB service) =====
-- Decode base-32 values; longer strings are split at 2^30 because the client's tonumber only handles 32-bit inputs
local function decodeValue(value)
    if #value > 6 then
        local low = tonumber(string.sub(value, -6), 32)
        local high = tonumber(string.sub(value, 1, -7), 32)
        if not low or not high then return nil end
        return low + high * (2 ^ 30)
    end
    return tonumber(value, 32)
end

-- Split "return {downloadTime=...,fields={...},data={{...}}}" into downloadTime, a fields index, and the raw rows
local function parseMetadata(payload)
    local metadataEnd = string.find(payload, ",data={", 1, true)
    if not metadataEnd then return nil end

    local chunk = loadstring(string.sub(payload, 1, metadataEnd - 1) .. "}")
    if not chunk then return nil end
    local ok, metadata = pcall(chunk)
    if not ok or type(metadata) ~= "table" or type(metadata.fields) ~= "table" then return nil end

    local fieldIndex = {}
    for i = 2, #metadata.fields do
        fieldIndex[metadata.fields[i]] = i - 1
    end
    if metadata.fields[1] ~= "itemString" then return nil end

    -- Skip past ",data={" (7 chars): keeping the outer brace corrupts the first row's itemString
    return metadata.downloadTime, fieldIndex, string.sub(payload, metadataEnd + 7)
end

-- Decode one payload, calling handler(dbKey, values[]) per plain-itemID row; suffixed item strings have no plain Auctionator key, so skip them
local function decodeRows(payload, handler)
    local downloadTime, fieldIndex, rows = parseMetadata(payload)
    if not downloadTime then return nil end

    for itemString, packed in string.gmatch(rows, "{\"?([^,\"]+)\"?,([^}]+)}") do
        if tonumber(itemString) then
            local values = {}
            local index = 1
            for value in string.gmatch(packed, "[^,]+") do
                values[index] = decodeValue(value)
                index = index + 1
            end
            handler(itemString, values)
        end
    end

    return downloadTime, fieldIndex
end

-- One dbKey → number table per requested field, each divided by its scale; nil when the header lacks a field
local function columns(payload, scales)
    local rows = {}
    local downloadTime, fields = decodeRows(payload, function(dbKey, values) rows[dbKey] = values end)
    if not downloadTime then return nil end

    local out = {}
    for name, scale in pairs(scales) do
        local index = fields[name]
        if not index then return nil end
        local column = {}
        for dbKey, values in pairs(rows) do
            column[dbKey] = (values[index] or 0) / scale
        end
        out[name] = column
    end
    return out, downloadTime
end

local function decodeCaptured()
    if captured[STAT_TAG] then
        local stat, downloadTime = columns(captured[STAT_TAG], { marketValue = 1 })
        if stat then
            feed.marketValue = stat.marketValue
            feed.downloadTime = downloadTime
        end
    end

    -- TSM stores the rate in thousandths; keep it as a percentage. The payload's sold-per-day column is zero for many items that clearly sell, so it is not used
    if captured[SALE_TAG] then
        local sale = columns(captured[SALE_TAG], { regionSalePercent = 10 })
        if sale then
            feed.salePercent = sale.regionSalePercent
        end
    end

    -- Prefer the data payload's stamp for the age: the app updates it every sync while the scan stat lags hours behind, and TSM itself reports this time
    if captured[DATA_TAG] then
        local downloadTime = parseMetadata(captured[DATA_TAG])
        if downloadTime and downloadTime > (feed.downloadTime or 0) then
            feed.downloadTime = downloadTime
        end
    end

    captured = {}
end

-- ===== Public accessors =====
-- Age of the app snapshot as short text ("3h" / "2d"); nil without data
function AP.TSMFeed.AgeText()
    if not feed.downloadTime then return nil end
    local age = math.max(time() - feed.downloadTime, 0)
    if age < 3600 then return math.floor(age / 60) .. "m" end
    if age < 86400 then return math.floor(age / 3600) .. "h" end
    return math.floor(age / 86400) .. "d"
end

-- Look up a link in one value table, most specific db key first; suffixed gear pools into its base item because TSM ships plain item IDs on this client, and zero means the app has no figure
local function valueForLink(values, itemLink)
    if not values then return nil end
    local dbKeys = AP.Bridge.DBKeys(itemLink)
    if not dbKeys then return nil end
    for _, dbKey in ipairs(dbKeys) do
        local value = values[dbKey]
        if value and value > 0 then return value end
    end
    return nil
end

-- 14-day smoothed realm market value in copper; nil when no scan-stat payload arrived
function AP.TSMFeed.MarketValueFor(itemLink)
    return valueForLink(feed.marketValue, itemLink)
end

-- Region-wide share of posted auctions that sell, in percent; nil without a figure
function AP.TSMFeed.SalePercentFor(itemLink)
    return valueForLink(feed.salePercent, itemLink)
end

-- Sale rate as whole-percent text ("39%"); nil without a figure
function AP.TSMFeed.SaleRateText(itemLink)
    local rate = AP.TSMFeed.SalePercentFor(itemLink)
    return rate and ("%d%%"):format(math.floor(rate + 0.5))
end

-- ===== Events =====
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName == "TradeSkillMaster_AppHelper" then
            self:UnregisterEvent("ADDON_LOADED")
        else
            installHook()
        end
    elseif event == "PLAYER_LOGIN" then
        decodeCaptured()
    end
end)
