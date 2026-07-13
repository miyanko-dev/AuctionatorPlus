local _, AP = ...

-- Append a setup hint when no TSM app data was captured this session; the data rows themselves live in PriceHistory.lua's tooltip block, and items merely absent from a live feed stay silent.

-- Loads last so the hint lands at the tooltip bottom; delete with TSMFeed.lua (plus .toc lines) to revoke TSM entirely.

local origApply = AP.Tooltip.Apply
AP.Tooltip.Apply = function(tooltip, itemLink)
  origApply(tooltip, itemLink)

  if AP.TSMFeed.HasData() then return end

  tooltip:AddLine(" ")
  tooltip:AddLine(
    "Installing TSM also shows the most relevant TSM market data here.",
    0.7, 0.7, 0.7, true)
  tooltip:Show()
end
