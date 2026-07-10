local _, AP = ...

-- Market data from the TSM desktop application, captured on the way into the
-- game. The app rewrites TradeSkillMaster_AppHelper/AppData.lua, which calls
-- the global TSM_APPHELPER_LOAD_DATA while addons load; this module wraps that
-- global (forwarding to TSM untouched), decodes the current realm's payloads,
-- and offers them as market values plus an optional import into Auctionator's
-- price database. Delete this file and TSMTrend.lua (plus their .toc lines) to
-- revoke the feature; neither Auctionator nor TSM is modified.
AP.TSMFeed = {}

local DATA_TAG = "AUCTIONDB_NON_COMMODITY_DATA"
local STAT_TAG = "AUCTIONDB_NON_COMMODITY_SCAN_STAT"

-- Per-character opt-ins, persisted in AuctionatorPlusDB by this module alone.
AP.TSMFeed.Settings = {
  useTrend = false,     -- trend columns compare against TSM market value
  importScans = false,  -- login merges the TSM snapshot into the price database
}

local captured = {}  -- raw payload strings per tag, current realm only
local feed = {
  marketValue = nil,   -- [dbKey] = smoothed market value (copper)
  snapshot = nil,      -- [dbKey] = { minBuyout, numAuctions }
  downloadTime = nil,  -- unix time the app downloaded the snapshot
}

-- ===== Payload capture =====

-- AppHelper compares realms case-insensitively with \226 (curly apostrophe
-- lead byte) squashed; the app's realm keys carry a -Faction suffix on era.
local function IsCurrentRealm(realm)
  local current = GetRealmName() .. "-" .. UnitFactionGroup("player")
  realm = string.gsub(realm, "\226", "'")
  current = string.gsub(current, "\226", "'")
  return string.lower(realm) == string.lower(current)
end

local function Capture(tag, realmOrRegion, payload)
  if type(tag) ~= "string" or type(realmOrRegion) ~= "string" or type(payload) ~= "string" then
    return
  end
  if (tag == DATA_TAG or tag == STAT_TAG) and IsCurrentRealm(realmOrRegion) then
    captured[tag] = payload
  end
end

-- Wrap the global delivery function, forwarding to whoever owned it. TSM
-- installs its own handler while it loads (after this addon, alphabetically),
-- so re-wrap on every ADDON_LOADED until AppHelper has delivered its data.
local installedHook

local function InstallHook()
  local current = TSM_APPHELPER_LOAD_DATA
  if current ~= nil and current == installedHook then return end
  local forward = current
  installedHook = function(tag, realmOrRegion, payload)
    Capture(tag, realmOrRegion, payload)
    if forward then forward(tag, realmOrRegion, payload) end
  end
  TSM_APPHELPER_LOAD_DATA = installedHook
end

InstallHook()

-- ===== Payload decoding (format as parsed by TSM's AuctionDB service) =====

-- Values are base-32; longer strings are split because the client's tonumber
-- only handles 32-bit inputs. Mirrors TradeSkillMaster/Core/Service/AuctionDB.
local function DecodeValue(value)
  if #value > 6 then
    local low = tonumber(string.sub(value, -6), 32)
    local high = tonumber(string.sub(value, 1, -7), 32)
    if not low or not high then return nil end
    return low + high * (2 ^ 30)
  end
  return tonumber(value, 32)
end

-- Payload shape: "return {downloadTime=...,fields={...},data={{...},{...}}}".
-- Returns downloadTime plus an iterator-ready fields index and the raw rows.
local function ParseMetadata(payload)
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

  -- Skip past ",data={" (7 chars) so the row list starts at the first row's
  -- own brace; keeping the outer brace corrupts the first row's itemString.
  return metadata.downloadTime, fieldIndex, string.sub(payload, metadataEnd + 7)
end

-- Decode one payload, calling handler(dbKey, values[]) per plain-itemID row.
-- Suffixed/bonused item strings have no plain Auctionator key, so skip them.
-- Returns downloadTime and the field-name -> value-position index.
local function DecodeRows(payload, handler)
  local downloadTime, fieldIndex, rows = ParseMetadata(payload)
  if not downloadTime then return nil end

  for itemString, packed in string.gmatch(rows, "{\"?([^,\"]+)\"?,([^}]+)}") do
    if tonumber(itemString) then
      local values = {}
      local index = 1
      for value in string.gmatch(packed, "[^,]+") do
        values[index] = DecodeValue(value)
        index = index + 1
      end
      handler(itemString, values)
    end
  end

  return downloadTime, fieldIndex
end

local function DecodeCaptured()
  if captured[DATA_TAG] then
    local snapshot = {}
    local downloadTime, fields = DecodeRows(captured[DATA_TAG], function(dbKey, values)
      snapshot[dbKey] = values
    end)
    if downloadTime and fields.minBuyout and fields.numAuctions then
      for dbKey, values in pairs(snapshot) do
        snapshot[dbKey] = {
          minBuyout = values[fields.minBuyout],
          numAuctions = values[fields.numAuctions],
          marketValueRecent = fields.marketValueRecent and values[fields.marketValueRecent],
        }
      end
      feed.snapshot = snapshot
      feed.downloadTime = downloadTime
    end
  end

  if captured[STAT_TAG] then
    local marketValue = {}
    local downloadTime, fields = DecodeRows(captured[STAT_TAG], function(dbKey, values)
      marketValue[dbKey] = values
    end)
    if downloadTime and fields.marketValue then
      for dbKey, values in pairs(marketValue) do
        marketValue[dbKey] = values[fields.marketValue]
      end
      feed.marketValue = marketValue
    end
  end

  captured = {}
end

-- ===== Public accessors =====

function AP.TSMFeed.HasData()
  return feed.marketValue ~= nil or feed.snapshot ~= nil
end

function AP.TSMFeed.DownloadTime()
  return feed.downloadTime
end

-- Age of the app snapshot as short text ("3h" / "2d"); nil without data.
function AP.TSMFeed.AgeText()
  if not feed.downloadTime then return nil end
  local age = time() - feed.downloadTime
  if age < 0 then age = 0 end
  if age < 3600 then return math.floor(age / 60) .. "m" end
  if age < 86400 then return math.floor(age / 3600) .. "h" end
  return math.floor(age / 86400) .. "d"
end

-- Smoothed TSM market value for an Auctionator db key; falls back to the
-- snapshot's recent market value when no scan-stat payload arrived.
function AP.TSMFeed.MarketValue(dbKey)
  if type(dbKey) ~= "string" then return nil end
  local value = feed.marketValue and feed.marketValue[dbKey]
  if not value then
    local entry = feed.snapshot and feed.snapshot[dbKey]
    value = entry and entry.marketValueRecent
  end
  if value and value > 0 then return value end
  return nil
end

-- Market value for an item link, most specific db key first (suffixed gear
-- pools into its base item because TSM ships plain item IDs on this client).
function AP.TSMFeed.MarketValueForLink(itemLink)
  local dbKeys = AP.Bridge.DBKeysForLink(itemLink)
  if not dbKeys then return nil end
  for _, dbKey in ipairs(dbKeys) do
    local value = AP.TSMFeed.MarketValue(dbKey)
    if value then return value end
  end
  return nil
end

-- ===== Import into Auctionator's price database =====

-- Feed the snapshot through Auctionator's own SetPrice, the code path a real
-- scan uses: it only adds today's day bucket and the last-seen price, so
-- existing history stays intact. Returns the item count, or nil when this
-- snapshot was already imported (tracked per character).
function AP.TSMFeed.ImportScanData()
  if not feed.snapshot or not feed.downloadTime then return nil end
  if not Auctionator.Database then return nil end
  if AuctionatorPlusDB.tsmLastImport == feed.downloadTime then return nil end

  local count = 0
  for dbKey, entry in pairs(feed.snapshot) do
    if entry.minBuyout and entry.minBuyout > 0 then
      Auctionator.Database:SetPrice(dbKey, entry.minBuyout, entry.numAuctions)
      count = count + 1
    end
  end

  AuctionatorPlusDB.tsmLastImport = feed.downloadTime
  return count
end

-- ===== Settings persistence (self-contained, per character) =====

local function LoadFeedSettings()
  if type(AuctionatorPlusDB) ~= "table" then
    AuctionatorPlusDB = {}
  end
  if type(AuctionatorPlusDB.tsmUseTrend) == "boolean" then
    AP.TSMFeed.Settings.useTrend = AuctionatorPlusDB.tsmUseTrend
  end
  if type(AuctionatorPlusDB.tsmImportScans) == "boolean" then
    AP.TSMFeed.Settings.importScans = AuctionatorPlusDB.tsmImportScans
  end
end

function AP.TSMFeed.SaveSettings()
  AuctionatorPlusDB.tsmUseTrend = AP.TSMFeed.Settings.useTrend
  AuctionatorPlusDB.tsmImportScans = AP.TSMFeed.Settings.importScans
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
      InstallHook()
    end

  elseif event == "PLAYER_LOGIN" then
    LoadFeedSettings()
    DecodeCaptured()

    if AP.TSMFeed.Settings.importScans then
      local count = AP.TSMFeed.ImportScanData()
      if count then
        print(string.format(
          "|cff88ccffAuctionatorPlus|r: merged %d TSM prices into the scan database (%s old).",
          count, AP.TSMFeed.AgeText() or "?"))
      end
    end
  end
end)
