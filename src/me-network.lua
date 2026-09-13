local component = require("component")

local componentTypes = {"me_interface", "me_controller", "fluid_interface"}

---@class FluidSnapshot
local Snapshot = {}
Snapshot.__index = Snapshot

---@param fluid Fluid
---@return {name: string, label: string, amount: integer}|nil
function Snapshot:find(fluid)
  return self.byName[fluid.name] or (fluid.label and self.byLabel[string.lower(fluid.label)]) or nil
end

---@param fluid Fluid
---@return integer
function Snapshot:amount(fluid)
  local stack = self:find(fluid)
  return stack and stack.amount or 0
end

---@param fluid Fluid
---@return string
function Snapshot:label(fluid)
  local stack = self:find(fluid)
  return stack and stack.label or fluid.label
end

---@class MeNetwork
local MeNetwork = {}
MeNetwork.__index = MeNetwork

---@type table<string, string>
MeNetwork.messages = {
  missing = "ME network unavailable: no ME Interface or ME Controller connected",
  unsupported = "ME network unavailable: connected interface cannot read the network, use a block ME Interface or an ME Controller",
  failed = "ME network unavailable: reading the network failed"
}

---Create a reader for fluids stored in an ME network
---@param address? string
---@return MeNetwork
function MeNetwork.new(address)
  return setmetatable({address = address, proxy = nil, online = false, status = "missing"}, MeNetwork)
end

---Addresses of a component type, limited to the configured address when one is set
---@param componentType string
---@return string[]
---@private
function MeNetwork:addresses(componentType)
  if self.address then
    local address = component.get(self.address, componentType)
    return address and {address} or {}
  end

  local addresses = {}

  for address in component.list(componentType, true) do
    table.insert(addresses, address)
  end

  return addresses
end

---Connect to the first component that can read fluids from the network
---@return boolean
---@private
function MeNetwork:connect()
  self.proxy = nil
  self.status = "missing"

  for _, componentType in ipairs(componentTypes) do
    for _, address in ipairs(self:addresses(componentType)) do
      local proxy = component.proxy(address)

      if proxy and proxy.getFluidsInNetwork then
        self.proxy = proxy
        return true
      end

      self.status = "unsupported"
    end
  end

  return false
end

---Read all fluids in the network
---@return FluidSnapshot|nil
function MeNetwork:read()
  if self.proxy == nil and not self:connect() then
    self.online = false
    return nil
  end

  local ok, stacks = pcall(self.proxy.getFluidsInNetwork)

  if not ok or type(stacks) ~= "table" then
    self.proxy = nil
    self.online = false
    self.status = "failed"
    return nil
  end

  local snapshot = setmetatable({byName = {}, byLabel = {}}, Snapshot)

  for _, stack in ipairs(stacks) do
    if type(stack) == "table" and stack.name then
      local entry = snapshot.byName[stack.name]

      if entry == nil then
        entry = {name = stack.name, label = stack.label or stack.name, amount = 0}
        snapshot.byName[stack.name] = entry
        snapshot.byLabel[string.lower(entry.label)] = entry
      end

      entry.amount = entry.amount + (stack.amount or 0)
    end
  end

  self.online = true
  self.status = "online"
  return snapshot
end

return MeNetwork
