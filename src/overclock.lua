local M = 1000000

local voltages = {32768, 131072, 524288, 2097152, 8388608}

---@class OverclockResult
---@field overclocks integer
---@field multiplier integer
---@field eut integer
---@field duration integer

local Overclock = {}

---@param value integer
---@return integer
local function log4(value)
  local result = 0

  while value >= 4 do
    value = math.floor(value / 4)
    result = result + 1
  end

  return result
end

---@param value integer
---@return integer
local function log4ceil(value)
  local result, power = 0, 1

  while power < value do
    power = power * 4
    result = result + 1
  end

  return result
end

---MK tier a recipe needs, from its startup EU and EU/t
---@param startupEu integer
---@param eut integer
---@return integer
function Overclock.recipeTier(startupEu, eut)
  local tier = 5

  if startupEu <= 160 * M then
    tier = 1
  elseif startupEu <= 320 * M then
    tier = 2
  elseif startupEu <= 640 * M then
    tier = 3
  elseif startupEu <= 5120 * M then
    tier = 4
  end

  if eut > voltages[4] then
    return 5
  elseif eut > voltages[3] then
    return math.max(tier, 4)
  elseif eut > voltages[2] then
    return math.max(tier, 3)
  elseif eut > voltages[1] then
    return math.max(tier, 2)
  end

  return tier
end

---Recipe EU/t and duration after the overclocks a reactor applies
---@param recipe Recipe
---@param tier integer Reactor MK tier from 1 to 5
---@param compact boolean
---@return OverclockResult
function Overclock.apply(recipe, tier, compact)
  local eut = math.floor(recipe.eut)
  local voltage = voltages[tier]
  local factor = tier >= 4 and 4 or 2
  local overclocks = math.min(tier - Overclock.recipeTier(recipe.startupEu, eut),
    log4(math.floor(voltage / math.max(eut, 32))))

  if not compact then
    overclocks = math.min(overclocks,
      math.max(log4ceil(math.floor(voltage / 8)), 1) - math.max(log4ceil(math.floor(eut / 8)), 1))
  end

  overclocks = math.max(overclocks, 0)

  local multiplier = math.floor(factor ^ overclocks)

  return {
    overclocks = overclocks,
    multiplier = multiplier,
    eut = eut * multiplier,
    duration = math.max(math.floor(recipe.duration / multiplier), 1)
  }
end

return Overclock
