FF.Constants = {
  DefaultMinROIPercent = 20,
  MinGapPercent = 15,
  AHCutPercent = 5,
  DepositPercent = 5,
  DefaultUndercutPercent = 2,
  HistoricalMultipleCap = 3,
  ScanTimeoutSeconds = 6,

  PanelWidth = 950,
  PanelHeight = 540,
  RowHeight = 28,

  Columns = {
    Item        = 180,
    RelQty      = 90,
    Underpriced = 80,
    Vol         = 45,
    Sellers     = 55,
    Cost        = 95,
    Profit      = 95,
    ROI         = 55,
    Gap         = 8,
  },

  Tooltip = {
    CallerID     = "AuctionatorPlus",
    AverageLabel = "Average Min. Buyout",
    TrendLabel   = "Trend",
  },

  StatPanel = {
    Width            = 540,
    Height           = 540,
    RowHeight        = 24,
    InputMaxLetters  = 120,
    Columns = {
      Item   = 180,
      Buyout = 90,
      Avg    = 95,
      Trend  = 60,
      Gap    = 8,
    },
  },
}
