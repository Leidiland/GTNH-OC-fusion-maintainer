local unicode = require("unicode")

local buttonStyles = {
  normal = {"text", "border"},
  active = {"background", "accent"}
}

---@class Canvas
local Canvas = {}
Canvas.__index = Canvas

---Create a canvas drawing through the GPU with themed colors and touch regions
---@param gpu table
---@param theme table<string, integer>
---@param width integer
---@param height integer
---@return Canvas
function Canvas.new(gpu, theme, width, height)
  return setmetatable({
    gpu = gpu,
    theme = theme,
    width = width,
    height = height,
    colors = {},
    regions = {},
    saved = nil,
    buffer = nil
  }, Canvas)
end

function Canvas:open()
  local gpu = self.gpu
  local width, height = gpu.getResolution()

  self.saved = {width = width, height = height, palette = {}}

  local names = {}

  for name in pairs(self.theme) do
    table.insert(names, name)
  end

  table.sort(names)

  local usePalette = gpu.getDepth() >= 4 and #names <= 16

  for index, name in ipairs(names) do
    if usePalette then
      local slot = index - 1
      self.saved.palette[slot] = gpu.getPaletteColor(slot)
      gpu.setPaletteColor(slot, self.theme[name])
      self.colors[name] = {slot, true}
    else
      self.colors[name] = {self.theme[name], false}
    end
  end

  gpu.setResolution(self.width, self.height)

  if gpu.allocateBuffer then
    self.buffer = gpu.allocateBuffer(self.width, self.height)
  end
end

function Canvas:close()
  local gpu = self.gpu

  if self.saved == nil then
    return
  end

  if self.buffer then
    gpu.setActiveBuffer(0)
    gpu.freeBuffer(self.buffer)
    self.buffer = nil
  end

  for slot, color in pairs(self.saved.palette) do
    gpu.setPaletteColor(slot, color)
  end

  gpu.setForeground(0xFFFFFF)
  gpu.setBackground(0x000000)
  gpu.setResolution(self.saved.width, self.saved.height)
  gpu.fill(1, 1, self.saved.width, self.saved.height, " ")

  self.saved = nil
end

function Canvas:begin()
  self.regions = {}
  self.foreground = nil
  self.background = nil

  if self.buffer then
    self.gpu.setActiveBuffer(self.buffer)
  end
end

function Canvas:finish()
  if self.buffer then
    self.gpu.setActiveBuffer(0)
    self.gpu.bitblt(0, 1, 1, self.width, self.height, self.buffer, 1, 1)
  end
end

---@param foreground string
---@param background string
---@private
function Canvas:setColors(foreground, background)
  if foreground ~= self.foreground then
    local color = self.colors[foreground]
    self.gpu.setForeground(color[1], color[2])
    self.foreground = foreground
  end

  if background ~= self.background then
    local color = self.colors[background]
    self.gpu.setBackground(color[1], color[2])
    self.background = background
  end
end

---@param x integer
---@param y integer
---@param width integer
---@param height integer
---@param background string
---@param character? string
---@param foreground? string
function Canvas:fill(x, y, width, height, background, character, foreground)
  if width <= 0 or height <= 0 then
    return
  end

  self:setColors(foreground or "text", background)
  self.gpu.fill(x, y, width, height, character or " ")
end

---@param x integer
---@param y integer
---@param text string
---@param foreground string
---@param background string
function Canvas:text(x, y, text, foreground, background)
  self:setColors(foreground, background)
  self.gpu.set(x, y, text)
end

---Draw a clickable button and return the column after it
---@param x integer
---@param y integer
---@param label string
---@param action function
---@param style? "normal"|"active"
---@return integer
function Canvas:button(x, y, label, action, style)
  local colors = buttonStyles[style or "normal"]
  local text = " "..label.." "
  local width = unicode.len(text)

  self:text(x, y, text, colors[1], colors[2])
  self:region(x, y, width, 1, action)

  return x + width
end

---@param x integer
---@param y integer
---@param width integer
---@param height integer
---@param action function
function Canvas:region(x, y, width, height, action)
  table.insert(self.regions, {x = x, y = y, width = width, height = height, action = action})
end

---Find the topmost region action at a position
---@param x integer
---@param y integer
---@return function|nil
function Canvas:hit(x, y)
  for index = #self.regions, 1, -1 do
    local region = self.regions[index]

    if x >= region.x and x < region.x + region.width and y >= region.y and y < region.y + region.height then
      return region.action
    end
  end

  return nil
end

return Canvas
