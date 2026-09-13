local unicode = require("unicode")

local format = {}

local suffixes = {"", "k", "M", "G", "T", "P"}
local multipliers = {k = 1e3, m = 1e6, g = 1e9, t = 1e12}

---Format an amount with a unit suffix, e.g. 1.25M
---@param value number|nil
---@return string
function format.amount(value)
  if value == nil then
    return "-"
  end

  local sign = value < 0 and "-" or ""
  value = math.abs(value)

  if value < 1000 then
    return sign..tostring(math.floor(value))
  end

  local index = 1

  while value >= 999.5 and index < #suffixes do
    value = value / 1000
    index = index + 1
  end

  local pattern = value >= 99.95 and "%.0f" or value >= 9.995 and "%.1f" or "%.2f"

  return sign..string.format(pattern, value)..suffixes[index]
end

---Parse an amount with an optional suffix, e.g. 250k or 1.5M
---@param text string
---@return integer|nil
function format.parseAmount(text)
  local number, suffix = string.match(string.lower(text or ""), "^%s*(%d*%.?%d+)%s*([kmgt]?)%s*$")
  local value = tonumber(number)

  if value == nil then
    return nil
  end

  return math.floor(value * (multipliers[suffix] or 1) + 0.5)
end

---Format a duration given in ticks
---@param ticks number
---@return string
function format.seconds(ticks)
  local seconds = (ticks or 0) / 20

  if seconds < 60 then
    return string.format("%.2f s", seconds)
  end

  return string.format("%dm %02ds", math.floor(seconds / 60), math.floor(seconds % 60))
end

---Pad or truncate text to an exact width
---@param text any
---@param width integer
---@param align? "left"|"right"|"center"
---@return string
function format.fit(text, width, align)
  text = tostring(text or "")

  if width <= 0 then
    return ""
  end

  local length = unicode.len(text)

  if length > width then
    return unicode.sub(text, 1, width - 1).."…"
  end

  local space = width - length

  if align == "right" then
    return string.rep(" ", space)..text
  elseif align == "center" then
    local left = math.floor(space / 2)
    return string.rep(" ", left)..text..string.rep(" ", space - left)
  end

  return text..string.rep(" ", space)
end

return format
