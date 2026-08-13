local _, AP = ...

-- Capture the TSM desktop app's market data for the tooltip: AppData.lua calls the global TSM_APPHELPER_LOAD_DATA while addons load, so wrap it (forwarding to TSM untouched) and decode the current realm's payloads.
-- Delete this file and TSMTrend.lua plus their .toc lines to revoke the feature.
AP.TSMFeed = {}

local DATA_TAG = "AUCTIONDB_NON_COMMODITY_DATA"
local STAT_TAG = "AUCTIONDB_NON_COMMODITY_SCAN_STAT"

local captured = {}  -- raw payload strings per tag, current realm only
local feed = {
    marketValue = nil,   -- [dbKey] = smoothed market value (copper)
    downloadTime = nil,  -- unix time the app downloaded the snapshot
}

-- ===== Payload capture =====
-- Match realms the way AppHelper does: case-insensitive, curly apostrophes squashed; the app's realm keys carry a -Faction suffix on era.
local function isCurrentRealm(realm)
    local current = GetRealmName() .. "-" .. UnitFactionGroup("player")
    realm = string.gsub(realm, "\226", "'")
    current = string.gsub(current, "\226", "'")
    return string.lower(realm) == string.lower(current)
end

local function capture(tag, realmOrRegion, payload)
    if type(tag) ~= "string" or type(realmOrRegion) ~= "string" or type(payload) ~= "string" then
        return
    end
    if (tag == DATA_TAG or tag == STAT_TAG) and isCurrentRealm(realmOrRegion) then
        captured[tag] = payload
    end
end

-- Re-wrap the global on every ADDON_LOADED until AppHelper has delivered: TSM installs its own handler while loading (after this addon, alphabetically).
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
-- Decode base-32 values; longer strings are split at 2^30 because the client's tonumber only handles 32-bit inputs.
local function decodeValue(value)
    if #value > 6 then
        local low = tonumber(string.sub(value, -6), 32)
        local high = tonumber(string.sub(value, 1, -7), 32)
        if not low or not high then return nil end
        return low + high * (2 ^ 30)
    end
    return tonumber(value, 32)
end

-- Split "return {downloadTime=...,fields={...},data={{...}}}" into downloadTime, a fields index, and the raw rows.
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

    -- Skip past ",data={" (7 chars): keeping the outer brace corrupts the first row's itemString.
    return metadata.downloadTime, fieldIndex, string.sub(payload, metadataEnd + 7)
end

-- Decode one payload, calling handler(dbKey, values[]) per plain-itemID row; suffixed item strings have no plain Auctionator key, so skip them.
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

local function decodeCaptured()
    if captured[STAT_TAG] then
        local marketValue = {}
        local downloadTime, fields = decodeRows(captured[STAT_TAG], function(dbKey, values)
            marketValue[dbKey] = values
        end)
        if downloadTime and fields.marketValue then
            for dbKey, values in pairs(marketValue) do
                marketValue[dbKey] = values[fields.marketValue]
            end
            feed.marketValue = marketValue
            feed.downloadTime = downloadTime
        end
    end

    -- Prefer the data payload's stamp for the age: the app updates it every sync while the scan stat lags hours behind, and TSM itself reports this time.
    if captured[DATA_TAG] then
        local downloadTime = parseMetadata(captured[DATA_TAG])
        if downloadTime and downloadTime > (feed.downloadTime or 0) then
            feed.downloadTime = downloadTime
        end
    end

    captured = {}
end

-- ===== Public accessors =====
function AP.TSMFeed.HasData()
    return feed.marketValue ~= nil
end

-- Age of the app snapshot in seconds; nil without data.
function AP.TSMFeed.AgeSeconds()
    if not feed.downloadTime then return nil end
    return math.max(time() - feed.downloadTime, 0)
end

-- Age of the app snapshot as short text ("3h" / "2d"); nil without data.
function AP.TSMFeed.AgeText()
    local age = AP.TSMFeed.AgeSeconds()
    if not age then return nil end
    if age < 3600 then return math.floor(age / 60) .. "m" end
    if age < 86400 then return math.floor(age / 3600) .. "h" end
    return math.floor(age / 86400) .. "d"
end

-- Look up a link in one value table, most specific db key first; suffixed gear pools into its base item because TSM ships plain item IDs on this client.
local function valueForLink(values, itemLink)
    if not values then return nil end
    local dbKeys = AP.Bridge.DBKeysForLink(itemLink)
    if not dbKeys then return nil end
    for _, dbKey in ipairs(dbKeys) do
        local value = values[dbKey]
        if value and value > 0 then return value end
    end
    return nil
end

-- 14-day smoothed market value; nil when no scan-stat payload arrived.
function AP.TSMFeed.SmoothedValueForLink(itemLink)
    return valueForLink(feed.marketValue, itemLink)
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
