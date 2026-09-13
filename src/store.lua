local filesystem = require("filesystem")
local serialization = require("serialization")

---@class ReactorSettings
---@field name string|nil
---@field recipe string|nil
---@field mode "auto"|"manual"
---@field low integer
---@field high integer

---@class Store
local Store = {}
Store.__index = Store

---Create a store persisting reactor settings to a file
---@param path string
---@return Store
function Store.new(path)
  return setmetatable({path = path, data = {version = 1, reactors = {}}}, Store)
end

function Store:load()
  local file = io.open(self.path, "r")

  if file == nil then
    return
  end

  local content = file:read("*a")
  file:close()

  local ok, data = pcall(serialization.unserialize, content)

  if ok and type(data) == "table" and type(data.reactors) == "table" then
    self.data = data
  end
end

---@return boolean
function Store:save()
  filesystem.makeDirectory(filesystem.path(self.path))

  local temporaryPath = self.path..".tmp"
  local file = io.open(temporaryPath, "w")

  if file == nil then
    return false
  end

  file:write(serialization.serialize(self.data))
  file:close()

  filesystem.remove(self.path)
  filesystem.rename(temporaryPath, self.path)

  return true
end

---Get settings of a reactor, created from defaults when missing
---@param address string
---@param defaults {lowThreshold: integer, highThreshold: integer}
---@return ReactorSettings
function Store:reactor(address, defaults)
  local settings = self.data.reactors[address]

  if settings == nil then
    settings = {mode = "manual", low = defaults.lowThreshold, high = defaults.highThreshold}
    self.data.reactors[address] = settings
  end

  return settings
end

return Store
