local component = require("component")

---@class DiscordLog
local DiscordLog = {}
DiscordLog.__index = DiscordLog

---Create a log posting to a Discord webhook
---@param url string
---@param name string
---@return DiscordLog
function DiscordLog.new(url, name)
  return setmetatable({url = url, name = name}, DiscordLog)
end

---@param entry LogEntry
function DiscordLog:write(entry)
  if not component.isAvailable("internet") then
    return
  end

  local internet = require("internet")
  local content = "**"..self.name.."** `"..entry.level.."` "..entry.message
  local ok, response = pcall(internet.request, self.url, {content = content})

  if ok and response then
    pcall(response)
  end
end

return DiscordLog
