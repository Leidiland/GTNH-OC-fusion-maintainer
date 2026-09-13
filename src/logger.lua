---@class LogEntry
---@field time integer
---@field level "debug"|"info"|"warning"|"error"
---@field message string

---@class Logger
local Logger = {}
Logger.__index = Logger

Logger.levels = {debug = 1, info = 2, warning = 3, error = 4}

---Create a logger
---@param clock Clock
---@return Logger
function Logger.new(clock)
  return setmetatable({clock = clock, handlers = {}}, Logger)
end

---Add a handler receiving entries at or above a level
---@param handler {write: fun(self, entry: LogEntry, clock: Clock)}
---@param level? "debug"|"info"|"warning"|"error"
function Logger:addHandler(handler, level)
  table.insert(self.handlers, {handler = handler, level = Logger.levels[level or "debug"]})
end

---Write an entry to all handlers
---@param level "debug"|"info"|"warning"|"error"
---@param message any
function Logger:log(level, message)
  local entry = {time = self.clock:now(), level = level, message = tostring(message)}

  for _, item in ipairs(self.handlers) do
    if Logger.levels[level] >= item.level then
      pcall(item.handler.write, item.handler, entry, self.clock)
    end
  end
end

function Logger:debug(message)
  self:log("debug", message)
end

function Logger:info(message)
  self:log("info", message)
end

function Logger:warning(message)
  self:log("warning", message)
end

function Logger:error(message)
  self:log("error", message)
end

return Logger
