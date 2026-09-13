local component = require("component")
local filesystem = require("filesystem")
local internet = require("internet")
local shell = require("shell")

local releaseUrl = "https://github.com/Leidiland/GTNH-OC-fusion-maintainer/releases/latest/download/FusionMaintainer.tar"
local tarUrl = "https://raw.githubusercontent.com/mpmxyz/ocprograms/master/home/bin/tar.lua"

local usage = [[
Usage: update [--config=<path>] [--reset-config]
  --config=<path>  Install the given file as config.lua
  --reset-config   Replace config.lua with the defaults]]

local root = filesystem.canonical(filesystem.path(shell.resolve(os.getenv("_") or "update.lua")))
local stagingPath = root.."/.update"
local configPath = root.."/config.lua"
local previousPath = package.path

package.path = root.."/?.lua;"..previousPath

local Config = require("src.config")

---Remove a file or directory recursively
---@param path string
local function remove(path)
  if filesystem.isDirectory(path) then
    for name in filesystem.list(path) do
      remove(filesystem.concat(path, name))
    end
  end

  filesystem.remove(path)
end

---Copy a file or directory recursively
---@param from string
---@param to string
local function copy(from, to)
  if filesystem.isDirectory(from) then
    filesystem.makeDirectory(to)

    for name in filesystem.list(from) do
      copy(filesystem.concat(from, name), filesystem.concat(to, name))
    end
  else
    local ok, reason = filesystem.copy(from, to)

    if not ok then
      error("Cannot write "..to..": "..tostring(reason), 0)
    end
  end
end

---Download a URL to a file
---@param url string
---@param path string
local function download(url, path)
  local file, reason = io.open(path, "wb")

  if file == nil then
    error("Cannot write "..path..": "..tostring(reason), 0)
  end

  local ok, requestError = pcall(function()
    for chunk in internet.request(url) do
      file:write(chunk)
    end
  end)

  file:close()

  if not ok then
    error("Download failed: "..tostring(requestError), 0)
  end
end

---Read the version returned by a version.lua file
---@param path string
---@return string
local function readVersion(path)
  local file = io.open(path, "r")

  if file == nil then
    return "unknown"
  end

  local chunk = load(file:read("*a"))
  file:close()

  if chunk == nil then
    return "unknown"
  end

  local ok, version = pcall(chunk)

  return ok and tostring(version) or "unknown"
end

---Replace the program with the latest release and apply the config options
---@param options table
local function update(options)
  if options.help or options.h then
    print(usage)
    return
  end

  for key in pairs(options) do
    if key ~= "config" and key ~= "reset-config" then
      error("Unknown option: "..key.."\n"..usage, 0)
    end
  end

  if options.config == true or options.config == "" then
    error("--config requires a path, for example --config=/home/fusion.lua", 0)
  end

  if options.config and options["reset-config"] then
    error("--config and --reset-config cannot be combined", 0)
  end

  if not component.isAvailable("internet") then
    error("An Internet Card is required", 0)
  end

  remove(stagingPath)
  filesystem.makeDirectory(stagingPath.."/files")

  if options.config then
    local source = shell.resolve(options.config)

    Config.read(source)
    copy(source, stagingPath.."/config.lua")
  end

  if not filesystem.exists("/bin/tar.lua") then
    print("Downloading tar")
    download(tarUrl, "/bin/tar.lua")
  end

  print("Downloading latest release")
  download(releaseUrl, stagingPath.."/release.tar")
  shell.execute("tar -xf "..stagingPath.."/release.tar --dir="..stagingPath.."/files")

  if not filesystem.exists(stagingPath.."/files/main.lua") then
    error("The release archive could not be extracted", 0)
  end

  local previousVersion = readVersion(root.."/version.lua")

  copy(stagingPath.."/files", root)
  print("Updated "..previousVersion.." to "..readVersion(root.."/version.lua"))

  if not options.config and not options["reset-config"] then
    print("config.lua kept")
    return
  end

  if filesystem.exists(configPath) then
    copy(configPath, configPath..".bak")
    print("Previous config.lua saved as config.lua.bak")
  end

  if options.config then
    copy(stagingPath.."/config.lua", configPath)
    print("config.lua replaced with "..options.config)
  else
    copy(root.."/config.default.lua", configPath)
    print("config.lua replaced with the defaults")
  end
end

local _, options = shell.parse(...)
local ok, reason = pcall(update, options)

remove(stagingPath)
package.path = previousPath

if not ok then
  io.stderr:write(tostring(reason).."\n")
end
