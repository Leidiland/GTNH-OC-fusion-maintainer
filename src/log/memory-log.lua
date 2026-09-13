---@class MemoryLog
local MemoryLog = {}
MemoryLog.__index = MemoryLog

---Create a log keeping the newest entries in memory
---@param size integer
---@return MemoryLog
function MemoryLog.new(size)
  return setmetatable({size = size, entries = {}}, MemoryLog)
end

---@param entry LogEntry
function MemoryLog:write(entry)
  table.insert(self.entries, 1, entry)

  if #self.entries > self.size then
    table.remove(self.entries)
  end
end

function MemoryLog:clear()
  self.entries = {}
end

return MemoryLog
