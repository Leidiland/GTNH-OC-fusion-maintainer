local component = require("component")
local computer = require("computer")
local event = require("event")

local Clock = require("src.clock")
local Controller = require("src.controller")
local DiscordLog = require("src.log.discord-log")
local FileLog = require("src.log.file-log")
local Logger = require("src.logger")
local MeNetwork = require("src.me-network")
local MemoryLog = require("src.log.memory-log")
local RecipeBook = require("src.recipe-book")
local Store = require("src.store")
local Summary = require("src.summary")
local Canvas = require("src.ui.canvas")
local View = require("src.ui.view")
local theme = require("src.ui.theme")

local watchedComponents = {gt_machine = true, me_interface = true, me_controller = true}
local discordName = "Fusion Maintainer"

---@class App
local App = {}
App.__index = App

App.width = 160
App.height = 50

---Create the application
---@param root string
---@param config table
---@param recipes table[]
---@param version string
---@return App
function App.new(root, config, recipes, version)
  return setmetatable({
    root = root,
    config = config,
    recipeData = recipes,
    version = version,
    running = false,
    dirty = true,
    nextPoll = 0,
    discoverAt = nil,
    discordLog = nil,
    summary = nil,
    dialog = nil
  }, App)
end

---@private
function App:init()
  local gpu = component.gpu
  local maxWidth, maxHeight = gpu.maxResolution()

  if maxWidth < App.width or maxHeight < App.height then
    error("A tier 3 graphics card and tier 3 screen are required", 0)
  end

  local config = self.config

  if #config.steps == 0 then
    error("config.lua: steps needs at least one value", 0)
  end

  if Logger.levels[config.log.discordLevel] == nil then
    error('config.lua: log.discordLevel must be "debug", "info", "warning" or "error"', 0)
  end

  if type(config.log.discordSummaryInterval) ~= "number" then
    error("config.lua: log.discordSummaryInterval must be a number of minutes", 0)
  end

  self.clock = Clock.new(config.log.timeZone)
  self.memoryLog = MemoryLog.new(64)
  self.logger = Logger.new(self.clock)
  self.logger:addHandler(self.memoryLog, "info")
  self.logger:addHandler(FileLog.new(self.root.."/"..config.log.file, config.log.maxFileSize), "info")

  if config.log.discordWebhookUrl ~= "" then
    self.discordLog = DiscordLog.new(config.log.discordWebhookUrl, discordName)
    self.logger:addHandler(self.discordLog, config.log.discordLevel)

    if config.log.discordSummaryInterval > 0 then
      self.summary = Summary.new(discordName, config.log.discordSummaryInterval)
    end
  end

  self.store = Store.new(self.root.."/data/reactors.dat")
  self.store:load()

  self.recipes = RecipeBook.new(self.recipeData, config.customRecipes)
  self.network = MeNetwork.new(config.network.address)
  self.controller = Controller.new(config, self.network, self.recipes, self.store, self.logger)

  self.canvas = Canvas.new(gpu, theme, App.width, App.height)
  self.canvas:open()
  self.view = View.new(self)

  self.logger:info("Started with "..#self.recipes.list.." recipes")
  self.controller:discover()
end

---Run the main loop until the program is quit
function App:run()
  self:init()
  self.running = true

  local renderedSecond = -1

  while self.running do
    local now = computer.uptime()

    if self.discoverAt and now >= self.discoverAt then
      self.discoverAt = nil
      self.controller:discover()
      self.nextPoll = now
    end

    if now >= self.nextPoll then
      self.controller:poll()
      self.nextPoll = now + self.config.pollInterval
      self.dirty = true

      if self.summary then
        self:sendSummary()
      end
    end

    if self.dirty or math.floor(now) ~= renderedSecond then
      self:render()
      self.dirty = false
      renderedSecond = math.floor(now)
    end

    if self.discordLog then
      self.discordLog:update()
    end

    local wait = math.min(self.nextPoll, math.floor(computer.uptime()) + 1) - computer.uptime()

    self:handle(event.pull(math.max(0.05, wait)))
  end
end

---@param name string|nil
---@private
function App:handle(name, ...)
  if name == "key_down" then
    local _, char, code = ...
    self:onKey(char, code)
  elseif name == "touch" then
    local _, x, y = ...
    self:onTouch(x, y)
  elseif name == "scroll" then
    local _, x, y, direction = ...
    self:onScroll(x, y, direction)
  elseif name == "component_added" or name == "component_removed" then
    local _, componentType = ...

    if watchedComponents[componentType] then
      self.discoverAt = computer.uptime() + 1
    end
  elseif name == "interrupted" then
    self:quit()
  end
end

---@private
function App:onKey(char, code)
  if self.dialog then
    self.dialog:key(char, code)
  else
    self.view:key(char, code)
  end

  self.dirty = true
end

---@private
function App:onTouch(x, y)
  local action = self.canvas:hit(x, y)

  if action then
    action()
    self.dirty = true
  end
end

---@private
function App:onScroll(x, y, direction)
  if self.dialog then
    if self.dialog.scroll then
      self.dialog:scroll(direction)
    end
  else
    self.view:scroll(x, y, direction)
  end

  self.dirty = true
end

---Queue the status overview when its interval has started
---@private
function App:sendSummary()
  local time = self.clock:now()

  if not self.summary:due(time) then
    return
  end

  for _, message in ipairs(self.summary:messages(self.clock:format("%Y-%m-%d %H:%M", time), self.controller, self.network)) do
    self.discordLog:send(message)
  end
end

---@private
function App:render()
  self.canvas:begin()
  self.view:render(self.canvas)

  if self.dialog then
    self.canvas.regions = {}
    self.dialog:render(self.canvas)
  end

  self.canvas:finish()
end

---Show a dialog on top of the view
---@param dialog table
function App:openDialog(dialog)
  dialog.close = function()
    if self.dialog == dialog then
      self.dialog = nil
    end

    self.dirty = true
  end

  self.dialog = dialog
  self.dirty = true
end

---Persist settings and apply them on the next poll
function App:settingsChanged()
  self.store:save()
  self.nextPoll = math.min(self.nextPoll, computer.uptime() + 1)
  self.dirty = true
end

function App:quit()
  self.running = false
end

function App:shutdown()
  if self.canvas then
    self.canvas:close()
  end

  if self.store then
    self.store:save()
  end

  if self.logger then
    self.logger:info("Stopped")
  end

  if self.discordLog then
    self.discordLog:flush(3)
  end
end

return App
