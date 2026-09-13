local filesystem = require("filesystem")

local stampPath = "/tmp/.fusion-maintainer-clock"

---@class Clock
local Clock = {}
Clock.__index = Clock

---Create a clock reading real-world time
---@param timeZone? number
---@return Clock
function Clock.new(timeZone)
  return setmetatable({offset = (timeZone or 0) * 3600}, Clock)
end

---Current real-world time in seconds
---@return integer
function Clock:now()
  local file = io.open(stampPath, "w")

  if file == nil then
    return 0
  end

  file:write("")
  file:close()

  return math.floor(filesystem.lastModified(stampPath) / 1000) + self.offset
end

---Format a time, defaults to now
---@param pattern? string
---@param time? integer
---@return string
function Clock:format(pattern, time)
  return os.date(pattern or "%H:%M:%S", time or self:now())
end

return Clock
