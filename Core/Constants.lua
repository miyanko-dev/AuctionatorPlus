FF.Constants = {
  PriceJumpRatio = 1.10,
  DefaultAHCutPercent = 5,
  ScanTimeoutSeconds = 6,

  PanelWidth = 800,
  PanelHeight = 585,
  RowHeight = 28,

  Columns = {
    Item   = 220,
    Qty    = 90,
    Order  = 90,
    Cost   = 90,
    Profit = 100,
    Gap    = 8,
  },

  SortOptions = {
    { key = "itemName",        label = "Item Name"  },
    { key = "displayQuantity", label = "Listed Qty" },
    { key = "totalQuantity",   label = "Order Qty"  },
    { key = "totalCost",       label = "Invest"     },
    { key = "margin",          label = "Profit"     },
  },

  SortDirections = {
    { key = "asc",  label = "Ascending"  },
    { key = "desc", label = "Descending" },
  },
}
