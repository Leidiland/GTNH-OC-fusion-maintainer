local filesystem = require("filesystem")
local shell = require("shell")

local root = filesystem.canonical(filesystem.path(shell.resolve(os.getenv("_") or "fluids.lua")))
local previousPath = package.path

package.path = root.."/?.lua;"..previousPath

local Config = require("src.config")
local MeNetwork = require("src.me-network")

package.path = previousPath

local args = shell.parse(...)
local filter = args[1] and string.lower(args[1]) or nil
local loaded, config = pcall(Config.load, root)

if not loaded then
  io.stderr:write(tostring(config).."\n")
  return
end

local network = MeNetwork.new(config.network.address)
local snapshot = network:read()

if snapshot == nil then
  io.stderr:write(MeNetwork.messages[network.status].."\n")
  return
end

local fluids = {}

for _, stack in pairs(snapshot.byName) do
  if filter == nil
    or string.find(string.lower(stack.name), filter, 1, true)
    or string.find(string.lower(stack.label), filter, 1, true) then
    table.insert(fluids, stack)
  end
end

table.sort(fluids, function(a, b) return a.name < b.name end)

for _, fluid in ipairs(fluids) do
  print(string.format("%-28s %-28s %d", fluid.name, fluid.label, math.floor(fluid.amount)))
end
