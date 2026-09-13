local filesystem = require("filesystem")

---@class Config
local Config = {}

---@param defaults table
---@param overrides table
---@return table
local function merge(defaults, overrides)
  for key, value in pairs(overrides) do
    local default = defaults[key]

    if type(value) == "table" and type(default) == "table" and #value == 0 and #default == 0 then
      merge(default, value)
    else
      defaults[key] = value
    end
  end

  return defaults
end

---Read a Lua file returning a table
---@param path string
---@return table
function Config.read(path)
  local file, reason = io.open(path, "r")

  if file == nil then
    error(path..": "..tostring(reason), 0)
  end

  local content = file:read("*a")
  file:close()

  local chunk, syntaxError = load(content, "="..path)

  if chunk == nil then
    error(syntaxError, 0)
  end

  local ok, value = pcall(chunk)

  if not ok then
    error(path..": "..tostring(value), 0)
  end

  if type(value) ~= "table" then
    error(path..": must return a table", 0)
  end

  return value
end

---Load config.lua on top of config.default.lua, creating config.lua on first start
---@param root string
---@return table
function Config.load(root)
  local defaultPath = root.."/config.default.lua"
  local path = root.."/config.lua"

  if not filesystem.exists(path) then
    filesystem.copy(defaultPath, path)
  end

  return merge(Config.read(defaultPath), Config.read(path))
end

return Config
