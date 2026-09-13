local computer = require("computer")

local format = require("src.format")
local Overclock = require("src.overclock")

---@class ReactorState
---@field label string
---@field tone "good"|"warn"|"bad"|"accent"|"muted"

---@class ReactorInput
---@field label string
---@field amount integer
---@field required integer
---@field missing boolean

---@class Reactor
local Reactor = {}
Reactor.__index = Reactor

---@type table<string, ReactorState>
Reactor.states = {
  running = {label = "Running", tone = "good"},
  starting = {label = "Starting", tone = "warn"},
  stalled = {label = "Stalled", tone = "bad"},
  idle = {label = "Idle", tone = "accent"},
  charging = {label = "Charging", tone = "warn"},
  noInputs = {label = "Missing inputs", tone = "bad"},
  lowCapacity = {label = "Capacity low", tone = "bad"},
  manual = {label = "Manual", tone = "muted"},
  noRecipe = {label = "No recipe", tone = "muted"},
  noNetwork = {label = "No ME data", tone = "bad"},
  offline = {label = "Offline", tone = "bad"}
}

local numerals = {"I", "II", "III", "IV", "V"}

---@class ReactorMachine
---@field kind string
---@field tier integer|nil
---@field compact boolean

---Detect a fusion controller type and MK tier from its machine name
---@param machineName string
---@return ReactorMachine|nil
function Reactor.detectMachine(machineName)
  local name = string.lower(machineName or "")
  local tier = tonumber(string.match(name, "fusioncomputer%.tier%.(%d+)"))

  if tier then
    tier = tier - 5
    return {kind = "Fusion MK "..(numerals[tier] or tostring(tier)), tier = tier, compact = false}
  end

  local compactTier = tonumber(string.match(name, "largefusioncomputer(%d+)"))

  if compactTier then
    return {kind = "Compact MK "..(numerals[compactTier] or tostring(compactTier)), tier = compactTier, compact = true}
  end

  return nil
end

---Create a reactor
---@param address string
---@param proxy table
---@param machine ReactorMachine
---@param settings ReactorSettings
---@param logger Logger
---@return Reactor
function Reactor.new(address, proxy, machine, settings, logger)
  return setmetatable({
    address = address,
    proxy = proxy,
    kind = machine.kind,
    tier = machine.tier,
    compact = machine.compact,
    settings = settings,
    logger = logger,
    recipe = nil,
    state = nil,
    stock = nil,
    outputLabel = nil,
    inputs = {},
    storedEu = 0,
    capacity = 0,
    workAllowed = false,
    active = false,
    inactiveSince = nil
  }, Reactor)
end

---@return string
function Reactor:displayName()
  return self.settings.name or (self.kind.." "..string.sub(self.address, 1, 4))
end

---Recipe EU/t and duration after overclocking in this reactor, base values when the tier is unknown
---@return OverclockResult|nil
function Reactor:overclockedRecipe()
  local recipe = self.recipe

  if recipe == nil then
    return nil
  end

  if self.tier == nil or self.tier < 1 or self.tier > 5 then
    return {overclocks = 0, multiplier = 1, eut = recipe.eut, duration = recipe.duration}
  end

  return Overclock.apply(recipe, self.tier, self.compact)
end

---@param name string|nil
function Reactor:setName(name)
  self.settings.name = (name ~= nil and name ~= "") and name or nil
end

---@param recipe Recipe|nil
function Reactor:setRecipe(recipe)
  self.recipe = recipe
  self.settings.recipe = recipe and recipe.id or nil
  self.stock = nil
  self.outputLabel = nil
  self.inputs = {}
end

---@param mode "auto"|"manual"
function Reactor:setMode(mode)
  self.settings.mode = mode
end

---Set the switch-on threshold, kept below the switch-off threshold
---@param value number
function Reactor:setLow(value)
  self.settings.low = math.max(0, math.min(math.floor(value), self.settings.high - 1))
end

---Set the switch-off threshold, kept above the switch-on threshold
---@param value number
function Reactor:setHigh(value)
  self.settings.high = math.max(math.floor(value), self.settings.low + 1)
end

---Read machine state and apply control
---@param snapshot FluidSnapshot|nil
---@param inputBatches integer
---@param stallTimeout? integer
function Reactor:update(snapshot, inputBatches, stallTimeout)
  if not self:readMachine() then
    self.inactiveSince = nil
    return self:setState("offline", "warning", "Controller not reachable")
  end

  if self.workAllowed and not self.active then
    self.inactiveSince = self.inactiveSince or computer.uptime()
  else
    self.inactiveSince = nil
  end

  local recipe = self.recipe

  if recipe == nil then
    return self:setState("noRecipe")
  end

  if snapshot == nil then
    return self:setState("noNetwork")
  end

  self:readFluids(snapshot, inputBatches)

  if self.settings.mode ~= "auto" then
    return self:setState("manual")
  end

  local settings = self.settings
  local missing = self:missingInputs()

  if self.workAllowed then
    if self.stock >= settings.high then
      self:setWorkAllowed(false)
      return self:setState("idle", "info", "Stock "..format.amount(self.stock).." mB reached, switched off")
    end

    if #missing > 0 then
      self:setWorkAllowed(false)
      return self:setState("noInputs", "warning", "Missing "..table.concat(missing, ", ")..", switched off")
    end

    if self.active then
      return self:setState("running")
    end

    if stallTimeout and stallTimeout > 0 and computer.uptime() - self.inactiveSince >= stallTimeout then
      return self:setState("stalled", "warning", "Switched on but not processing for "..stallTimeout.." s")
    end

    return self:setState("starting")
  end

  if self.stock >= settings.low then
    return self:setState("idle")
  end

  if #missing > 0 then
    return self:setState("noInputs", "warning", "Missing "..table.concat(missing, ", "))
  end

  if recipe.startupEu > self.capacity then
    return self:setState("lowCapacity", "warning",
      "Startup "..format.amount(recipe.startupEu).." EU exceeds capacity "..format.amount(self.capacity).." EU")
  end

  if self.storedEu < recipe.startupEu then
    return self:setState("charging")
  end

  self:setWorkAllowed(true)
  return self:setState("starting", "info", "Stock "..format.amount(self.stock).." mB, switched on")
end

---@return boolean
---@private
function Reactor:readMachine()
  return pcall(function()
    self.workAllowed = self.proxy.isWorkAllowed()
    self.active = self.proxy.isMachineActive()
    self.storedEu = self.proxy.getEUStored()
    self.capacity = self.proxy.getEUCapacity()
  end)
end

---@param snapshot FluidSnapshot
---@param inputBatches integer
---@private
function Reactor:readFluids(snapshot, inputBatches)
  self.stock = snapshot:amount(self.recipe.output)
  self.outputLabel = snapshot:label(self.recipe.output)
  self.inputs = {}

  for _, fluid in ipairs(self.recipe.inputs) do
    local amount = snapshot:amount(fluid)
    local required = fluid.amount * inputBatches

    table.insert(self.inputs, {
      label = snapshot:label(fluid),
      amount = amount,
      required = required,
      missing = amount < required
    })
  end
end

---@return string[]
---@private
function Reactor:missingInputs()
  local missing = {}

  for _, input in ipairs(self.inputs) do
    if input.missing then
      table.insert(missing, input.label)
    end
  end

  return missing
end

---Enable or disable the machine, returns false when the controller cannot be reached
---@param allowed boolean
---@return boolean
function Reactor:setWorkAllowed(allowed)
  if pcall(self.proxy.setWorkAllowed, allowed) then
    self.workAllowed = allowed
    return true
  end

  return false
end

---@param key string
---@param level? "info"|"warning"
---@param message? string
---@private
function Reactor:setState(key, level, message)
  local changed = self.state ~= key
  self.state = key

  if changed and message then
    self.logger:log(level, self:displayName()..": "..message)
  end
end

return Reactor
