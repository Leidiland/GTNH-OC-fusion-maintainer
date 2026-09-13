local filesystem = require("filesystem")
local shell = require("shell")

local root = filesystem.canonical(filesystem.path(shell.resolve(os.getenv("_") or "main.lua")))
local previousPath = package.path

package.path = root.."/?.lua;"..previousPath

for name in pairs(package.loaded) do
  if name:find("^src%.") or name == "recipes" or name == "version" then
    package.loaded[name] = nil
  end
end

local App = require("src.app")
local Config = require("src.config")

local loaded, config = pcall(Config.load, root)

if not loaded then
  package.path = previousPath
  io.stderr:write(tostring(config).."\n")
  return
end

local app = App.new(root, config, require("recipes"), require("version"))
local ok, reason = xpcall(function() app:run() end, debug.traceback)

app:shutdown()
package.path = previousPath

if not ok and not tostring(reason):find("interrupted") then
  io.stderr:write(tostring(reason).."\n")
end
