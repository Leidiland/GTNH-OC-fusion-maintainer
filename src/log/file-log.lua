local filesystem = require("filesystem")

---@class FileLog
local FileLog = {}
FileLog.__index = FileLog

---Create a log appending to a file with rotation
---@param path string
---@param maxSize integer
---@return FileLog
function FileLog.new(path, maxSize)
  return setmetatable({path = path, maxSize = maxSize}, FileLog)
end

---@param entry LogEntry
---@param clock Clock
function FileLog:write(entry, clock)
  if filesystem.exists(self.path) and filesystem.size(self.path) > self.maxSize then
    filesystem.remove(self.path..".old")
    filesystem.rename(self.path, self.path..".old")
  end

  local file = io.open(self.path, "a")

  if file == nil then
    return
  end

  file:write(clock:format("%Y-%m-%d %H:%M:%S", entry.time).." ["..entry.level.."] "..entry.message.."\n")
  file:close()
end

return FileLog
