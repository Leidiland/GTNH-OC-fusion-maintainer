local format = require("src.format")

local maxLength = 2000

local columns = {
  {title = "REACTOR", width = 20},
  {title = "OUTPUT", width = 26},
  {title = "STOCK", width = 8, align = "right"},
  {title = "OFF AT", width = 8, align = "right"},
  {title = "LEVEL", width = 6, align = "right"},
  {title = "STATE", width = 16}
}

---@param values string[]
---@return string
local function row(values)
  local cells = {}

  for index, column in ipairs(columns) do
    cells[index] = format.fit((string.gsub(values[index], "`", "'")), column.width, column.align)
  end

  return (string.gsub(table.concat(cells, "  "), "%s+$", ""))
end

---@class Summary
local Summary = {}
Summary.__index = Summary

---Create a periodic status overview for Discord
---@param name string
---@param interval number Minutes between overviews
---@return Summary
function Summary.new(name, interval)
  return setmetatable({name = name, interval = interval, slot = nil}, Summary)
end

---True on the first call and once per interval after that, aligned to the clock
---@param time integer
---@return boolean
function Summary:due(time)
  local slot = math.floor(time / (self.interval * 60))

  if slot == self.slot then
    return false
  end

  self.slot = slot
  return true
end

---Messages with the ME network and every reactor, split to fit the Discord message length
---@param time string
---@param controller Controller
---@param network MeNetwork
---@return string[]
function Summary:messages(time, controller, network)
  local titles = {}

  for index, column in ipairs(columns) do
    titles[index] = column.title
  end

  local header = row(titles)
  local text = "**"..self.name.."** status "..time.."\nME network "..(network.online and "online" or "offline")
    .." · "..controller.running.." / "..#controller.reactors.." enabled\n```\n"..header
  local messages = {}

  for _, reactor in ipairs(controller.reactors) do
    local level = reactor:level()
    local line = row({
      reactor:displayName(),
      reactor:outputName() or "No recipe",
      format.amount(reactor.stock),
      format.amount(reactor.settings.high),
      level and level.."%" or "-",
      reactor:stateInfo().label
    })

    if #text + #line + 5 > maxLength then
      table.insert(messages, text.."\n```")
      text = "```\n"..header
    end

    text = text.."\n"..line
  end

  table.insert(messages, text.."\n```")
  return messages
end

return Summary
