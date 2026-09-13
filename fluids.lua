local component = require("component")
local shell = require("shell")

local args = shell.parse(...)
local filter = args[1] and string.lower(args[1]) or nil

local proxy = nil

for _, componentType in ipairs({"me_interface", "me_controller"}) do
  if component.isAvailable(componentType) then
    proxy = component.getPrimary(componentType)
    break
  end
end

if proxy == nil then
  io.stderr:write("ME interface or ME controller not found\n")
  return
end

local fluids = {}

for _, stack in pairs(proxy.getFluidsInNetwork() or {}) do
  if type(stack) == "table" and stack.name ~= nil then
    local label = stack.label or ""

    if filter == nil
      or string.find(string.lower(stack.name), filter, 1, true)
      or string.find(string.lower(label), filter, 1, true) then
      table.insert(fluids, {name = stack.name, label = label, amount = stack.amount})
    end
  end
end

table.sort(fluids, function(a, b) return a.name < b.name end)

for _, fluid in ipairs(fluids) do
  print(string.format("%-28s %-28s %d", fluid.name, fluid.label, math.floor(fluid.amount)))
end
