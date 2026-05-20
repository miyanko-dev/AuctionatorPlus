FF.Bracket = {}

function FF.Bracket.Find(listings, ratio)
  table.sort(listings, function(a, b) return a.unitPrice < b.unitPrice end)

  for i = 2, #listings do
    local priceRatio = listings[i].unitPrice / listings[i - 1].unitPrice
    if priceRatio >= ratio then
      local bracket = {}
      for j = 1, i - 1 do
        bracket[j] = listings[j]
      end
      return bracket, listings[i].unitPrice
    end
  end

  return nil, nil
end

function FF.Bracket.Summarize(bracket, topPrice, cut)
  local totalCost = 0
  local totalQuantity = 0
  for _, listing in ipairs(bracket) do
    totalCost = totalCost + listing.cost
    totalQuantity = totalQuantity + listing.quantity
  end
  local margin = totalQuantity * topPrice * (1 - cut) - totalCost
  return {
    topPrice = topPrice,
    margin = margin,
    totalCost = totalCost,
    totalQuantity = totalQuantity,
  }
end
