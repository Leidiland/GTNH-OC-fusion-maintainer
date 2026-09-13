local unicode = require("unicode")

local format = require("src.format")
local keys = require("src.ui.keys")

local dialogs = {}

---Draw a centered dialog frame and return its top-left corner
---@param canvas Canvas
---@param width integer
---@param height integer
---@param title string
---@return integer, integer
local function drawFrame(canvas, width, height, title)
  local x = math.floor((canvas.width - width) / 2) + 1
  local y = math.floor((canvas.height - height) / 2) + 1

  canvas:region(1, 1, canvas.width, canvas.height, function() end)
  canvas:fill(x - 1, y - 1, width + 2, height + 2, "border")
  canvas:fill(x, y, width, height, "surfaceRaised")
  canvas:fill(x, y, width, 1, "accent")
  canvas:text(x + 2, y, format.fit(title, width - 4), "background", "accent")

  return x, y
end

---Width of a button drawn by Canvas:button
---@param label string
---@return integer
local function buttonWidth(label)
  return unicode.len(label) + 2
end

---@class InputDialog
---@field close function
local InputDialog = {}
InputDialog.__index = InputDialog

---Create a single line input dialog
---@param options {title: string, prompt: string, value: string, allowed?: string, maxLength?: integer, parse: fun(text: string): any, string|nil, submit: fun(value: any)}
---@return InputDialog
function dialogs.input(options)
  return setmetatable({options = options, text = options.value or "", pristine = true, error = nil}, InputDialog)
end

---@private
function InputDialog:submit()
  local value, message = self.options.parse(self.text)

  if message then
    self.error = message
    return
  end

  self.options.submit(value)
  self.close()
end

---@param char integer
---@param code integer
function InputDialog:key(char, code)
  if code == keys.escape then
    self.close()
  elseif code == keys.enter or code == keys.numpadEnter then
    self:submit()
  elseif code == keys.back then
    self.text = self.pristine and "" or unicode.sub(self.text, 1, -2)
    self.pristine = false
    self.error = nil
  elseif char and char >= 32 then
    local character = unicode.char(char)
    local allowed = self.options.allowed

    if allowed == nil or character:match(allowed) then
      if self.pristine then
        self.text = ""
        self.pristine = false
      end

      if unicode.len(self.text) < (self.options.maxLength or 24) then
        self.text = self.text..character
        self.error = nil
      end
    end
  end
end

---@param canvas Canvas
function InputDialog:render(canvas)
  local width, height = 64, 9
  local x, y = drawFrame(canvas, width, height, self.options.title)

  canvas:text(x + 2, y + 2, format.fit(self.options.prompt, width - 4), "muted", "surfaceRaised")
  canvas:fill(x + 2, y + 4, width - 4, 1, "background")

  if self.pristine and self.text ~= "" then
    canvas:text(x + 3, y + 4, format.fit(self.text, math.min(unicode.len(self.text), width - 6)), "text", "selection")
  else
    canvas:text(x + 3, y + 4, format.fit(self.text.."▌", width - 6), "text", "background")
  end

  if self.error then
    canvas:text(x + 2, y + 5, format.fit(self.error, width - 4), "bad", "surfaceRaised")
  end

  local cancelLabel, submitLabel = "Cancel  Esc", "OK  Enter"
  local buttonX = x + width - 2 - buttonWidth(cancelLabel) - 1 - buttonWidth(submitLabel)

  buttonX = canvas:button(buttonX, y + 7, cancelLabel, function() self.close() end) + 1
  canvas:button(buttonX, y + 7, submitLabel, function() self:submit() end, "active")
end

---@class RecipeDialog
---@field close function
local RecipeDialog = {}
RecipeDialog.__index = RecipeDialog

local recipeColumns = {
  {title = "OUTPUT", width = 30},
  {title = "INPUTS", width = 48},
  {title = "STARTUP", width = 10, align = "right"},
  {title = "USAGE", width = 12, align = "right"},
  {title = "TIME", width = 9, align = "right"},
  {title = "", width = 6}
}

---Create a searchable recipe picker
---@param options {title: string, book: RecipeBook, current: Recipe|nil, submit: fun(recipe: Recipe|nil)}
---@return RecipeDialog
function dialogs.recipe(options)
  local self = setmetatable({options = options, query = "", index = 1, offset = 0, entries = {}}, RecipeDialog)

  self:refresh()

  for index, entry in ipairs(self.entries) do
    if entry == options.current then
      self.index = index
    end
  end

  return self
end

---@private
function RecipeDialog:refresh()
  self.entries = {false}

  for _, recipe in ipairs(self.options.book:search(self.query)) do
    table.insert(self.entries, recipe)
  end

  self.index = (self.query ~= "" and #self.entries > 1) and 2 or 1
  self.offset = 0
end

---@param index? integer
---@private
function RecipeDialog:choose(index)
  local entry = self.entries[index or self.index]

  if entry == nil then
    return
  end

  self.options.submit(entry or nil)
  self.close()
end

---@param delta integer
---@private
function RecipeDialog:move(delta)
  self.index = math.max(1, math.min(#self.entries, self.index + delta))
end

---@param char integer
---@param code integer
function RecipeDialog:key(char, code)
  if code == keys.escape then
    self.close()
  elseif code == keys.enter or code == keys.numpadEnter then
    self:choose()
  elseif code == keys.up then
    self:move(-1)
  elseif code == keys.down then
    self:move(1)
  elseif code == keys.pageUp then
    self:move(-10)
  elseif code == keys.pageDown then
    self:move(10)
  elseif code == keys.home then
    self.index = 1
  elseif code == keys["end"] then
    self.index = #self.entries
  elseif code == keys.back then
    self.query = unicode.sub(self.query, 1, -2)
    self:refresh()
  elseif char and char >= 32 and unicode.len(self.query) < 36 then
    self.query = self.query..unicode.char(char)
    self:refresh()
  end
end

---@param direction integer
function RecipeDialog:scroll(direction)
  self:move(-direction)
end

---@param canvas Canvas
function RecipeDialog:render(canvas)
  local width, height = 128, 40
  local x, y = drawFrame(canvas, width, height, self.options.title)
  local rows = height - 9

  canvas:text(x + 2, y + 2, "Search", "muted", "surfaceRaised")
  canvas:fill(x + 10, y + 2, 40, 1, "background")
  canvas:text(x + 11, y + 2, format.fit(self.query.."▌", 38), "text", "background")
  canvas:text(x + 52, y + 2, (#self.entries - 1).." recipes", "muted", "surfaceRaised")

  local columnX = x + 2

  for _, column in ipairs(recipeColumns) do
    canvas:text(columnX, y + 4, format.fit(column.title, column.width, column.align), "muted", "surfaceRaised")
    columnX = columnX + column.width + 1
  end

  if self.index <= self.offset then
    self.offset = self.index - 1
  elseif self.index > self.offset + rows then
    self.offset = self.index - rows
  end

  for row = 1, rows do
    local index = row + self.offset
    local entry = self.entries[index]

    if entry == nil then
      break
    end

    local rowY = y + 4 + row
    local selected = index == self.index
    local background = selected and "selection" or "surfaceRaised"
    local cells

    if entry then
      local inputs = {}

      for _, input in ipairs(entry.inputs) do
        table.insert(inputs, input.label)
      end

      cells = {
        {entry.output.label, "text"},
        {table.concat(inputs, " + "), "text"},
        {format.amount(entry.startupEu).." EU", "text"},
        {format.amount(entry.eut).." EU/t", "muted"},
        {format.seconds(entry.duration), "muted"},
        {entry.custom and "custom" or "", "accent"}
      }
    else
      cells = {{"No recipe", "muted"}, {"Automatic control off", "muted"}}
    end

    canvas:fill(x + 1, rowY, width - 2, 1, background)
    columnX = x + 2

    for columnIndex, column in ipairs(recipeColumns) do
      local cell = cells[columnIndex]

      if cell then
        canvas:text(columnX, rowY, format.fit(cell[1], column.width, column.align), cell[2], background)
      end

      columnX = columnX + column.width + 1
    end

    canvas:region(x + 1, rowY, width - 2, 1, function()
      if self.index == index then
        self:choose(index)
      else
        self.index = index
      end
    end)
  end

  canvas:text(x + 2, y + height - 2, "Type to search   ↑↓ PgUp PgDn move   Enter or click twice to select   Esc cancel",
    "muted", "surfaceRaised")

  local cancelLabel = "Cancel  Esc"
  canvas:button(x + width - 2 - buttonWidth(cancelLabel), y + height - 2, cancelLabel, function() self.close() end)
end

return dialogs
