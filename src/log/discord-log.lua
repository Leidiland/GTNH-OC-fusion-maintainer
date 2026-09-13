local component = require("component")
local computer = require("computer")

local requestTimeout = 10
local maxQueue = 20
local escapes = {['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"}

---@param text string
---@return string
local function jsonString(text)
  local escaped = string.gsub(text, '[%c"\\]', function(character)
    return escapes[character] or string.format("\\u%04x", string.byte(character))
  end)

  return '"'..escaped..'"'
end

---@class DiscordLog
local DiscordLog = {}
DiscordLog.__index = DiscordLog

---Create a log posting to a Discord webhook in the background
---@param url string
---@param name string
---@return DiscordLog
function DiscordLog.new(url, name)
  return setmetatable({url = url, name = name, queue = {}, request = nil, startedAt = 0}, DiscordLog)
end

---Queue an entry, dropping the oldest one when the queue is full
---@param entry LogEntry
function DiscordLog:write(entry)
  if #self.queue >= maxQueue then
    table.remove(self.queue, 1)
  end

  table.insert(self.queue, "**"..self.name.."** `"..entry.level.."` "..entry.message)
end

---Finish the running request and start the next one without blocking, called from the main loop
function DiscordLog:update()
  local request = self.request

  if request then
    local ok, connected = pcall(request.finishConnect)
    local done = not ok or computer.uptime() - self.startedAt >= requestTimeout

    if not done and connected then
      local responded, code = pcall(request.response)
      done = not responded or code ~= nil
    end

    if not done then
      return
    end

    pcall(request.close)
    self.request = nil
  end

  if #self.queue == 0 or not component.isAvailable("internet") then
    return
  end

  local body = '{"content":'..jsonString(table.remove(self.queue, 1))..'}'
  local ok, handle = pcall(component.internet.request, self.url, body, {["Content-Type"] = "application/json"})

  if ok and handle then
    self.request = handle
    self.startedAt = computer.uptime()
  end
end

---Send queued entries before the program exits, waiting at most the given time
---@param seconds number
function DiscordLog:flush(seconds)
  local deadline = computer.uptime() + seconds

  while (self.request or #self.queue > 0) and computer.uptime() < deadline do
    self:update()
    os.sleep(0.05)
  end
end

return DiscordLog
