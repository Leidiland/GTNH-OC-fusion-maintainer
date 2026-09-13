local component = require("component")

local Reactor = require("src.reactor")

---@class Controller
local Controller = {}
Controller.__index = Controller

---Create the controller managing all reactors
---@param config table
---@param network MeNetwork
---@param recipes RecipeBook
---@param store Store
---@param logger Logger
---@return Controller
function Controller.new(config, network, recipes, store, logger)
  return setmetatable({
    config = config,
    network = network,
    recipes = recipes,
    store = store,
    logger = logger,
    reactors = {},
    snapshot = nil,
    running = 0,
    polled = false
  }, Controller)
end

---Find connected fusion controllers and keep existing reactor objects
function Controller:discover()
  local found = {}

  local function consider(address, required)
    local ok, machineName = pcall(component.invoke, address, "getName")
    local kind = ok and Reactor.detectKind(machineName) or nil

    if kind == nil and required and ok then
      kind = "Fusion"
    end

    if kind then
      found[address] = kind
    end
  end

  if self.config.reactors.discover then
    for address in component.list("gt_machine", true) do
      consider(address, false)
    end
  end

  for _, partialAddress in ipairs(self.config.reactors.addresses or {}) do
    local address = component.get(partialAddress, "gt_machine")

    if address then
      consider(address, true)
    else
      self.logger:warning("Configured controller "..partialAddress.." not found")
    end
  end

  local existing = {}

  for _, reactor in ipairs(self.reactors) do
    existing[reactor.address] = reactor
  end

  local reactors = {}

  for address, kind in pairs(found) do
    local reactor = existing[address]

    if reactor == nil then
      local settings = self.store:reactor(address, self.config.defaults)

      reactor = Reactor.new(address, component.proxy(address), kind, settings, self.logger)
      reactor.recipe = self.recipes:get(settings.recipe)

      if settings.recipe and reactor.recipe == nil then
        self.logger:warning(reactor:displayName()..": Saved recipe "..settings.recipe.." is not in the recipe table")
      end

      self.logger:info("Detected "..reactor:displayName())
    end

    existing[address] = nil
    table.insert(reactors, reactor)
  end

  for _, reactor in pairs(existing) do
    self.logger:warning(reactor:displayName().." disconnected")
  end

  table.sort(reactors, function(a, b)
    local nameA, nameB = a:displayName(), b:displayName()

    if nameA ~= nameB then
      return nameA < nameB
    end

    return a.address < b.address
  end)

  self.reactors = reactors
  self.store:save()
end

---Read the network and update all reactors
function Controller:poll()
  local wasOnline = self.network.online

  self.snapshot = self.network:read()

  if not self.polled or self.network.online ~= wasOnline then
    if self.network.online then
      self.logger:info("ME network connected")
    else
      self.logger:warning("ME network unavailable")
    end
  end

  local running = 0

  for _, reactor in ipairs(self.reactors) do
    reactor:update(self.snapshot, self.config.defaults.inputBatches)

    if reactor.workAllowed then
      running = running + 1
    end
  end

  self.running = running
  self.polled = true
end

return Controller
