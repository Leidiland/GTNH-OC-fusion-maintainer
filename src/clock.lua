local computer = require("computer")
local filesystem = require("filesystem")

local stampPath = "/tmp/.fusion-maintainer-clock"
local syncInterval = 60

---Real-world time in seconds from the modification time of a temporary file
---@return number|nil
local function readRealTime()
  local file = io.open(stampPath, "w")

  if file == nil then
    return nil
  end

  file:write("")
  file:close()

  return filesystem.lastModified(stampPath) / 1000
end

---@class Clock
local Clock = {}
Clock.__index = Clock

---Create a clock reading real-world time
---@param timeZone? number
---@return Clock
function Clock.new(timeZone)
  return setmetatable({offset = (timeZone or 0) * 3600, syncedAt = nil, syncedTime = 0}, Clock)
end

---Current real-world time in seconds, synced once a minute and advanced with the uptime in between
---@return integer
function Clock:now()
  local uptime = computer.uptime()

  if self.syncedAt == nil or uptime - self.syncedAt >= syncInterval then
    local time = readRealTime()

    if time then
      self.syncedAt = uptime
      self.syncedTime = time
    end
  end

  return math.floor(self.syncedTime + uptime - (self.syncedAt or uptime)) + self.offset
end

---Format a time, defaults to now
---@param pattern? string
---@param time? integer
---@return string
function Clock:format(pattern, time)
  return os.date(pattern or "%H:%M:%S", time or self:now())
end

return Clock
