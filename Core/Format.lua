FF.Format = {}

function FF.Format.StripItemColor(name)
  if not name then return "" end
  name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return name:lower()
end

function FF.Format.CleanItemText(text)
  if not text then return "?" end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  text = text:gsub("|T[^|]+|t", "")
  text = text:gsub("|H[^|]+|h", ""):gsub("|h", "")
  return strtrim(text)
end

function FF.Format.LabelForKey(list, key)
  for _, opt in ipairs(list) do
    if opt.key == key then return opt.label end
  end
  return ""
end

function FF.Format.Money(copper)
  if not copper or copper <= 0 then
    return "0g"
  end
  if Auctionator and Auctionator.Utilities and Auctionator.Utilities.CreatePaddedMoneyString then
    return Auctionator.Utilities.CreatePaddedMoneyString(copper)
  end
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  if g > 0 and s > 0 then return string.format("%dg %ds", g, s) end
  if g > 0 then return string.format("%dg", g) end
  return string.format("%ds", s)
end

function FF.Format.SanitizeSearchTerm(text)
  if type(text) ~= "string" then return nil end
  text = text:gsub("|c[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]", "")
  text = text:gsub("|C[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]", "")
  text = text:gsub("|r", ""):gsub("|R", "")
  text = text:gsub("|H[^|]+|h", ""):gsub("|h", "")
  text = text:gsub("|T.-|t", ""):gsub("|t", "")
  text = text:gsub("|A.-|a", ""):gsub("|a", "")
  text = text:gsub("%s+", " ")
  text = strtrim(text)
  if text == "" then return nil end
  return text
end
