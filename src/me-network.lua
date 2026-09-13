local component = require("component")

local componentTypes = {"me_interface", "me_controller"}

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

---Create a reader for fluids stored in an ME network
---@param address? string
---@return MeNetwork
function MeNetwork.new(address)
  return setmetatable({address = address, proxy = nil, online = false}, MeNetwork)
end

---@return boolean
---@private
function MeNetwork:connect()
  for _, componentType in ipairs(componentTypes) do
    local address

    if self.address then
      address = component.get(self.address, componentType)
    else
      address = component.list(componentType, true)()
    end

    if address then
      self.proxy = component.proxy(address)
      return true
    end
  end

  self.proxy = nil
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
  return snapshot
end

return MeNetwork
