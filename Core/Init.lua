FF = FF or {}

FF.collected = {}
FF.seenKeys = {}
FF.scanned = {}
FF.flips = {}

FF.panel = nil
FF.toggleButton = nil
FF.hasScanned = false

FF.sortProperty = "totalCost"
FF.sortDirection = "asc"

FF.committedRatio = 1.10
FF.committedMaxInvest = 0
FF.committedMinQuantity = 1
FF.committedMaxOrderQty = 0
FF.committedMinProfit = 0
FF.committedMaxQtyPct = 0
FF.committedCut = 0.05
