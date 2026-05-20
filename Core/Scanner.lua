FF.Scanner = {
  scanning = false,
  totalToScan = 0,
  scannedCount = 0,
}

function FF.Scanner.ResetCollected()
  FF.collected = {}
  FF.seenKeys = {}
  FF.scanned = {}
  FF.flips = {}
  FF.hasScanned = false
  FF.Scanner.scanning = false
  if FF.panel then
    FF.panel:SetScanningUI(false)
    FF.panel:ClearStatus()
    FF.panel:Render()
  end
end

function FF.Scanner.CollectEntries(entries)
  if type(entries) ~= "table" then return end
  for _, entry in ipairs(entries) do
    if entry and entry.totalQuantity and entry.totalQuantity > 0 then
      local key = FF.Adapter and FF.Adapter.KeyForEntry and FF.Adapter.KeyForEntry(entry)
      if key and not FF.seenKeys[key] then
        FF.seenKeys[key] = true
        table.insert(FF.collected, entry)
      end
    end
  end
end

function FF.Scanner.Abort()
  if not FF.Adapter then return end
  if FF.Adapter.AbortScan then FF.Adapter.AbortScan() end
  local wasScanning = FF.Scanner.scanning
  FF.Scanner.scanning = false
  if FF.panel then
    FF.panel:SetScanningUI(false)
    if wasScanning then
      FF.panel:SetStatus("Scan cancelled")
    else
      FF.panel:ClearStatus()
    end
  end
end

local function onListingsReady(entry, listings)
  if not FF.Scanner.scanning then return end

  if listings and #listings >= 2 then
    local record = { entry = entry, listings = listings }
    table.insert(FF.scanned, record)

    local flip = FF.Filters.BuildFlip(record)
    if flip then
      table.insert(FF.flips, flip)
      if FF.panel then FF.panel:Render() end
    end
  end

  FF.Scanner.scannedCount = FF.Scanner.scannedCount + 1
  if FF.panel then
    FF.panel:UpdateProgress(FF.Scanner.scannedCount, FF.Scanner.totalToScan)
  end
end

local function onComplete()
  FF.Scanner.scanning = false
  FF.hasScanned = true
  if FF.panel then
    FF.panel:SetScanningUI(false)
    FF.panel:CompleteProgress(FF.Scanner.scannedCount, FF.Scanner.totalToScan)
    FF.panel:Render()
  end
end

function FF.Scanner.Start()
  if not FF.Adapter then return end
  FF.Scanner.Abort()
  FF.Filters.Commit()

  FF.scanned = {}
  FF.flips = {}
  FF.Scanner.scannedCount = 0
  FF.Scanner.totalToScan = #FF.collected

  if FF.Scanner.totalToScan == 0 then
    if FF.panel then
      FF.panel:SetScanningUI(false)
      FF.panel:ClearStatus()
      FF.panel:Render()
    end
    return
  end

  FF.Scanner.scanning = true
  if FF.panel then
    FF.panel:SetScanningUI(true)
    FF.panel:StartProgress(FF.Scanner.totalToScan)
    FF.panel:Render()
  end

  FF.Adapter.ScanEntries(FF.collected, onListingsReady, onComplete)
end
