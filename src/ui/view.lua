local unicode = require("unicode")

local format = require("src.format")
local Reactor = require("src.reactor")
local dialogs = require("src.ui.dialogs")
local keys = require("src.ui.keys")

local layout = {
  header = 1,
  reactorsTitle = 3,
  reactorsHeader = 4,
  reactorsTop = 5,
  reactorsRows = 19,
  detailTitle = 25,
  detailTop = 26,
  detailSplit = 81,
  controlsX = 84,
  eventsTitle = 37,
  eventsTop = 38,
  eventsRows = 11,
  footer = 50
}

local columns = {
  {id = "power", title = "", width = 4},
  {id = "name", title = "REACTOR", width = 20, sort = function(reactor) return string.lower(reactor:displayName()) end},
  {id = "kind", title = "TYPE", width = 14, align = "center", sort = function(reactor) return reactor.kind end},
  {id = "output", title = "OUTPUT", width = 26, align = "center", sort = function(reactor)
    return reactor.recipe and string.lower(reactor.outputLabel or reactor.recipe.output.label) or ""
  end},
  {id = "level", title = "STOCK LEVEL", width = 24, align = "center", sort = function(reactor)
    return reactor.stock and reactor.stock / math.max(reactor.settings.high, 1) or -1
  end},
  {id = "stock", title = "STOCK", width = 8, align = "center", sort = function(reactor) return reactor.stock or -1 end},
  {id = "low", title = "ON BELOW", width = 8, align = "center", sort = function(reactor) return reactor.settings.low end},
  {id = "high", title = "OFF AT", width = 8, align = "center", sort = function(reactor) return reactor.settings.high end},
  {id = "energy", title = "EU STORED", width = 9, align = "center", sort = function(reactor) return reactor.storedEu end},
  {id = "state", title = "STATE", width = 16, headerAlign = "center", sort = function(reactor)
    return (Reactor.states[reactor.state] or Reactor.states.noRecipe).label
  end}
}

local columnsById = {}

for _, column in ipairs(columns) do
  columnsById[column.id] = column
end

local columnGap = 2

local levelStyles = {
  debug = {"DEBUG", "muted"},
  info = {"INFO", "info"},
  warning = {"WARN", "warn"},
  error = {"ERROR", "bad"}
}

local hints = {
  {"↑↓", "Select"},
  {"←→", "Field"},
  {"+ -", "Adjust"},
  {"[ ]", "Step"},
  {"Enter", "Type value"},
  {"R", "Recipe"},
  {"N", "Rename"},
  {"M", "Mode"},
  {"O", "On/Off"},
  {"PgUp PgDn", "Events"},
  {"Del", "Clear events"},
  {"Q", "Quit"}
}

---@param canvas Canvas
---@param y integer
---@param title string
---@param note? string
local function drawSectionTitle(canvas, y, title, note)
  local x = 2

  canvas:text(x, y, title, "accent", "background")
  x = x + unicode.len(title) + 1

  local noteWidth = note and unicode.len(note) + 1 or 0

  canvas:fill(x, y, canvas.width - x - noteWidth, 1, "background", "─", "border")

  if note then
    canvas:text(canvas.width - unicode.len(note), y, note, "muted", "background")
  end
end

---Draw a thin marker on a bar
---@param canvas Canvas
---@param x integer
---@param y integer
---@param filledUntil integer
---@param tone string
local function drawMarker(canvas, x, y, filledUntil, tone)
  canvas:text(x, y, "┃", "text", x < filledUntil and tone or "track")
end

---Draw the stock bar with threshold markers and the stock as a percentage of the switch-off threshold
---@param canvas Canvas
---@param x integer
---@param y integer
---@param width integer
---@param stock integer
---@param low integer
---@param high integer
---@param tone string
local function drawStockLevel(canvas, x, y, width, stock, low, high, tone)
  local scale = math.max(high * 1.25, stock, 1)
  local filled = math.min(width, math.floor(stock / scale * width + 0.5))
  local lowX = x + math.min(width - 1, math.floor(low / scale * width))
  local highX = x + math.min(width - 1, math.floor(high / scale * width))
  local label = math.min(100, math.floor(stock / math.max(high, 1) * 100 + 0.5)).."%"
  local labelX = x + math.floor((width - #label) / 2)
  local markers = {[lowX] = "markerLow", [highX] = "markerHigh"}

  canvas:fill(x, y, filled, 1, tone)
  canvas:fill(x + filled, y, width - filled, 1, "track")
  canvas:fill(lowX, y, 1, 1, "markerLow")
  canvas:fill(highX, y, 1, 1, "markerHigh")

  for index = 1, #label do
    local cellX = labelX + index - 1
    local background = markers[cellX] or (cellX < x + filled and tone) or "track"

    canvas:text(cellX, y, string.sub(label, index, index), background == "track" and "text" or "background", background)
  end
end

---Draw the stored EU bar with a marker at the recipe startup EU
---@param canvas Canvas
---@param x integer
---@param y integer
---@param width integer
---@param stored integer
---@param capacity integer
---@param startup integer
local function drawEnergyLevel(canvas, x, y, width, stored, capacity, startup)
  local scale = math.max(capacity, 1)
  local filled = math.min(width, math.floor(stored / scale * width + 0.5))
  local tone = stored >= startup and "good" or "warn"

  canvas:fill(x, y, filled, 1, tone)
  canvas:fill(x + filled, y, width - filled, 1, "track")

  if startup > 0 and startup <= capacity then
    drawMarker(canvas, x + math.min(width - 1, math.floor(startup / scale * width)), y, x + filled, tone)
  end
end

---Draw the on/off button of a reactor
---@param canvas Canvas
---@param x integer
---@param y integer
---@param on boolean
---@param outside string
local function drawPowerButton(canvas, x, y, on, outside)
  local color = on and "track" or "border"

  canvas:pill(x, y, 4, color, outside)
  canvas:text(x + 1, y, "⏻", on and "markerHigh" or "muted", color)
end

---@class View
local View = {}
View.__index = View

---Create the main dashboard view
---@param app App
---@return View
function View.new(app)
  return setmetatable({
    app = app,
    selected = nil,
    field = "low",
    sortColumn = "name",
    sortDescending = false,
    stepIndex = math.min(2, #app.config.steps),
    reactorsOffset = 0,
    eventsOffset = 0
  }, View)
end

---Reactors in the current sort order, sorted once per frame while rendering
---@return Reactor[]
function View:reactors()
  if self.sorted then
    return self.sorted
  end

  local column = columnsById[self.sortColumn]
  local reactors = {}
  local keys = {}

  for index, reactor in ipairs(self.app.controller.reactors) do
    reactors[index] = reactor
    keys[reactor] = column.sort(reactor)
  end

  table.sort(reactors, function(a, b)
    local keyA, keyB = keys[a], keys[b]

    if keyA ~= keyB then
      if self.sortDescending then
        return keyA > keyB
      end

      return keyA < keyB
    end

    return a.address < b.address
  end)

  return reactors
end

---Sort by a column, reversing the order when it is already sorted by it
---@param id string
function View:sortBy(id)
  if self.sortColumn == id then
    self.sortDescending = not self.sortDescending
  else
    self.sortColumn = id
    self.sortDescending = false
  end
end

---Index and reactor of the selection, selecting the first reactor when nothing is selected
---@return integer|nil, Reactor|nil
function View:selection()
  local reactors = self:reactors()

  for index, reactor in ipairs(reactors) do
    if reactor.address == self.selected then
      return index, reactor
    end
  end

  if reactors[1] then
    self.selected = reactors[1].address
    return 1, reactors[1]
  end

  return nil, nil
end

---Move the selection by a number of rows
---@param delta integer
function View:moveSelection(delta)
  local reactors = self:reactors()
  local index = self:selection()

  if index then
    self.selected = reactors[math.max(1, math.min(#reactors, index + delta))].address
  end
end

---Change the active threshold by the current step
---@param reactor Reactor
---@param direction integer
function View:adjust(reactor, direction)
  local step = self.app.config.steps[self.stepIndex]

  if self.field == "low" then
    reactor:setLow(reactor.settings.low + direction * step)
  else
    reactor:setHigh(reactor.settings.high + direction * step)
  end

  self.app:settingsChanged()
end

---Set the control mode and log the change
---@param reactor Reactor
---@param mode "auto"|"manual"
function View:setMode(reactor, mode)
  if reactor.settings.mode == mode then
    return
  end

  reactor:setMode(mode)
  self.app.logger:info(reactor:displayName()..": Mode set to "..mode)
  self.app:settingsChanged()
end

---Switch a reactor on or off by hand, which sets it to manual mode
---@param reactor Reactor
---@param allowed boolean
function View:setWorkAllowed(reactor, allowed)
  self:setMode(reactor, "manual")

  if reactor.workAllowed == allowed then
    return
  end

  if reactor:setWorkAllowed(allowed) then
    self.app.logger:info(reactor:displayName()..": Switched "..(allowed and "on" or "off").." by hand")
  else
    self.app.logger:warning(reactor:displayName()..": Controller not reachable")
  end

  self.app:settingsChanged()
end

---Open the dialog to type an exact threshold
---@param reactor Reactor
---@param field "low"|"high"
function View:openThreshold(reactor, field)
  self.field = field

  local isLow = field == "low"

  self.app:openDialog(dialogs.input({
    title = (isLow and "Switch on below" or "Switch off at").." · "..reactor:displayName(),
    prompt = "Amount in mB, e.g. 250k, 1.5M or 2G",
    value = tostring(reactor.settings[field]),
    allowed = "[%d%.kKmMgGtT]",
    maxLength = 16,
    parse = function(text)
      local value = format.parseAmount(text)

      if value == nil then
        return nil, "Enter a number such as 250k or 1.5M"
      elseif isLow and value >= reactor.settings.high then
        return nil, "Must be lower than the switch-off amount of "..format.amount(reactor.settings.high).." mB"
      elseif not isLow and value <= reactor.settings.low then
        return nil, "Must be higher than the switch-on amount of "..format.amount(reactor.settings.low).." mB"
      end

      return value
    end,
    submit = function(value)
      if isLow then
        reactor:setLow(value)
      else
        reactor:setHigh(value)
      end

      self.app:settingsChanged()
    end
  }))
end

---Open the rename dialog
---@param reactor Reactor
function View:openRename(reactor)
  self.app:openDialog(dialogs.input({
    title = "Rename · "..reactor:displayName(),
    prompt = "Leave empty to use the default name.",
    value = reactor.settings.name or "",
    maxLength = 20,
    parse = function(text)
      return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
    end,
    submit = function(name)
      reactor:setName(name)
      self.app:settingsChanged()
    end
  }))
end

---Open the recipe picker
---@param reactor Reactor
function View:openRecipe(reactor)
  self.app:openDialog(dialogs.recipe({
    title = "Select recipe · "..reactor:displayName(),
    book = self.app.recipes,
    current = reactor.recipe,
    submit = function(recipe)
      reactor:setRecipe(recipe)
      self.app.logger:info(reactor:displayName()..": Recipe set to "..(recipe and recipe.output.label or "none"))
      self.app:settingsChanged()
    end
  }))
end

---Handle a key press
---@param char integer
---@param code integer
function View:key(char, code)
  local character = (char and char > 0) and string.lower(unicode.char(char)) or ""
  local _, reactor = self:selection()

  if code == keys.up then
    self:moveSelection(-1)
  elseif code == keys.down then
    self:moveSelection(1)
  elseif code == keys.left or code == keys.right then
    self.field = self.field == "low" and "high" or "low"
  elseif code == keys.pageUp then
    self.eventsOffset = math.max(0, self.eventsOffset - layout.eventsRows)
  elseif code == keys.pageDown then
    self.eventsOffset = self.eventsOffset + layout.eventsRows
  elseif code == keys.delete then
    self.app.memoryLog:clear()
  elseif character == "q" then
    self.app:quit()
  elseif character == "[" then
    self.stepIndex = math.max(1, self.stepIndex - 1)
  elseif character == "]" then
    self.stepIndex = math.min(#self.app.config.steps, self.stepIndex + 1)
  elseif reactor == nil then
    return
  elseif character == "+" or character == "=" or code == keys.numpadAdd then
    self:adjust(reactor, 1)
  elseif character == "-" or code == keys.numpadSubtract then
    self:adjust(reactor, -1)
  elseif code == keys.enter or code == keys.numpadEnter then
    self:openThreshold(reactor, self.field)
  elseif character == "r" then
    self:openRecipe(reactor)
  elseif character == "n" then
    self:openRename(reactor)
  elseif character == "m" then
    self:setMode(reactor, reactor.settings.mode == "auto" and "manual" or "auto")
  elseif character == "o" then
    self:setWorkAllowed(reactor, not reactor.workAllowed)
  end
end

---Handle the mouse wheel
---@param x integer
---@param y integer
---@param direction integer
function View:scroll(x, y, direction)
  if y >= layout.reactorsTop and y < layout.reactorsTop + layout.reactorsRows then
    self:moveSelection(-direction)
  elseif y >= layout.eventsTop and y < layout.eventsTop + layout.eventsRows then
    self.eventsOffset = math.max(0, self.eventsOffset - direction * 3)
  end
end

---Draw the whole dashboard
---@param canvas Canvas
function View:render(canvas)
  self.sorted = nil
  self.sorted = self:reactors()

  canvas:fill(1, 1, canvas.width, canvas.height, "background")

  self:renderHeader(canvas)
  self:renderReactors(canvas)
  self:renderDetail(canvas)
  self:renderEvents(canvas)
  self:renderFooter(canvas)

  self.sorted = nil
end

---@param canvas Canvas
---@private
function View:renderHeader(canvas)
  local app = self.app
  local controller = app.controller
  local online = app.network.online

  canvas:fill(1, layout.header, canvas.width, 1, "surface")
  canvas:text(2, layout.header, "FUSION MAINTAINER", "accent", "surface")
  canvas:text(21, layout.header, "v"..app.version, "muted", "surface")

  local parts = {
    {"ME network ", "muted"},
    {online and "● online" or "● offline", online and "good" or "bad"},
    {"    Enabled ", "muted"},
    {controller.running.." / "..#controller.reactors, "text"},
    {"    "..app.clock:format("%H:%M:%S").." ", "text"}
  }

  local width = 0

  for _, part in ipairs(parts) do
    width = width + unicode.len(part[1])
  end

  local x = canvas.width - width + 1

  for _, part in ipairs(parts) do
    canvas:text(x, layout.header, part[1], part[2], "surface")
    x = x + unicode.len(part[1])
  end
end

---@param canvas Canvas
---@private
function View:renderReactors(canvas)
  local reactors = self:reactors()
  local index = self:selection()

  if index and index <= self.reactorsOffset then
    self.reactorsOffset = index - 1
  elseif index and index > self.reactorsOffset + layout.reactorsRows then
    self.reactorsOffset = index - layout.reactorsRows
  end

  local note = #reactors.." connected"

  if #reactors > layout.reactorsRows then
    note = (self.reactorsOffset + 1).."-"..math.min(#reactors, self.reactorsOffset + layout.reactorsRows).." of "..note
  end

  drawSectionTitle(canvas, layout.reactorsTitle, "REACTORS", note)

  local x = 4

  for _, column in ipairs(columns) do
    if column.sort then
      local id = column.id
      local sorted = id == self.sortColumn
      local arrow = self.sortDescending and "▼" or "▲"
      local title = column.title

      if sorted and unicode.len(title) + 2 <= column.width then
        title = title.." "..arrow
      elseif sorted then
        canvas:text(x + column.width, layout.reactorsHeader, arrow, "accent", "background")
      end

      canvas:text(x, layout.reactorsHeader, format.fit(title, column.width, column.headerAlign or column.align),
        sorted and "accent" or "muted", "background")
      canvas:region(x, layout.reactorsHeader, column.width, 1, function() self:sortBy(id) end)
    end

    x = x + column.width + columnGap
  end

  if index == nil then
    canvas:text(4, layout.reactorsTop + 1,
      "No fusion controllers found. Connect controllers to the computer with adapters or MFUs.", "muted", "background")
    return
  end

  for row = 1, layout.reactorsRows do
    local reactor = reactors[row + self.reactorsOffset]

    if reactor == nil then
      break
    end

    self:renderReactorRow(canvas, layout.reactorsTop + row - 1, reactor, row)
  end
end

---@param canvas Canvas
---@param y integer
---@param reactor Reactor
---@param row integer
---@private
function View:renderReactorRow(canvas, y, reactor, row)
  local selected = reactor.address == self.selected
  local background = selected and "selection" or (row % 2 == 0 and "surface" or "background")
  local state = Reactor.states[reactor.state] or Reactor.states.noRecipe
  local settings = reactor.settings
  local recipe = reactor.recipe

  canvas:pill(1, y, canvas.width, background, "background")

  if selected then
    canvas:text(2, y, "▶", "accent", background)
  end

  local energyTone = "muted"

  if recipe then
    energyTone = reactor.storedEu >= recipe.startupEu and "good" or "warn"
  end

  local cells = {
    name = {reactor:displayName(), "text"},
    kind = {reactor.kind, "muted"},
    output = {recipe and (reactor.outputLabel or recipe.output.label) or "No recipe", recipe and "info" or "muted"},
    stock = {format.amount(reactor.stock), "text"},
    low = {format.amount(settings.low), "text"},
    high = {format.amount(settings.high), "text"},
    energy = {format.amount(reactor.storedEu), energyTone},
    state = {"● "..state.label, state.tone}
  }

  local x = 4
  local powerX

  for _, column in ipairs(columns) do
    if column.id == "power" then
      powerX = x
      drawPowerButton(canvas, x, y, reactor.workAllowed, background)
    elseif column.id == "level" then
      if reactor.stock then
        drawStockLevel(canvas, x, y, column.width, reactor.stock, settings.low, settings.high, state.tone)
      end
    else
      local cell = cells[column.id]
      canvas:text(x, y, format.fit(cell[1], column.width, column.align), cell[2], background)
    end

    x = x + column.width + columnGap
  end

  local address = reactor.address

  canvas:region(1, y, canvas.width, 1, function()
    self.selected = address
  end)
  canvas:region(powerX, y, columnsById.power.width, 1, function()
    self.selected = address
    self:setWorkAllowed(reactor, not reactor.workAllowed)
  end)
end

---@param canvas Canvas
---@private
function View:renderDetail(canvas)
  local _, reactor = self:selection()

  drawSectionTitle(canvas, layout.detailTitle, "SELECTED", reactor and reactor.address or nil)

  if reactor == nil then
    return
  end

  canvas:fill(layout.detailSplit, layout.detailTop, 1, 10, "background", "│", "border")

  self:renderRecipe(canvas, reactor, 2, layout.detailTop)
  self:renderControls(canvas, reactor, layout.controlsX, layout.detailTop)
end

---@param canvas Canvas
---@param reactor Reactor
---@param x integer
---@param y integer
---@private
function View:renderRecipe(canvas, reactor, x, y)
  local state = Reactor.states[reactor.state] or Reactor.states.noRecipe
  local name = reactor:displayName()
  local width = layout.detailSplit - x - 2

  canvas:text(x, y, name, "text", "background")
  canvas:text(x + unicode.len(name) + 2, y, reactor.kind, "muted", "background")
  canvas:text(x + 38, y, "● "..state.label, state.tone, "background")
  canvas:text(x + 58, y, "Machine "..(reactor.active and "active" or "idle"), "muted", "background")

  canvas:fill(x, y + 1, width, 3, "surfaceRaised")

  local recipe = reactor.recipe

  if recipe == nil then
    canvas:text(x + 2, y + 2, "No recipe selected. Press R to choose the recipe this reactor runs.", "muted", "surfaceRaised")
    return
  end

  local inputLabels = {}

  for _, input in ipairs(recipe.inputs) do
    table.insert(inputLabels, input.label)
  end

  local inputText = table.concat(inputLabels, " + ").."  →  "
  local textWidth = width - 12
  local inputWidth = math.min(unicode.len(inputText), textWidth)

  canvas:text(x + 2, y + 2, "RECIPE", "accent", "surfaceRaised")
  canvas:text(x + 10, y + 2, format.fit(inputText, inputWidth), "text", "surfaceRaised")
  canvas:text(x + 10 + inputWidth, y + 2, format.fit(recipe.output.label, textWidth - inputWidth), "info", "surfaceRaised")

  local overclocked = reactor:overclockedRecipe()
  local usage = format.amount(overclocked.eut).." EU/t"
  local time = format.seconds(overclocked.duration)

  canvas:text(x, y + 4, "STARTUP", "muted", "background")
  canvas:text(x + 10, y + 4, format.amount(recipe.startupEu).." EU", "text", "background")
  canvas:text(x + 26, y + 4, "USAGE", "muted", "background")
  canvas:text(x + 33, y + 4, usage, "text", "background")
  canvas:text(x + 50, y + 4, "TIME", "muted", "background")
  canvas:text(x + 56, y + 4, time, "text", "background")

  if overclocked.overclocks > 0 then
    canvas:text(x + 34 + unicode.len(usage), y + 4, "×"..overclocked.multiplier, "accent", "background")
    canvas:text(x + 57 + unicode.len(time), y + 4, "÷"..overclocked.multiplier, "accent", "background")
  end

  canvas:text(x, y + 6, format.fit("FLUID", 44)..format.fit("IN ME", 14, "right")..format.fit("REQUIRED", 14, "right"),
    "muted", "background")

  canvas:text(x, y + 7, format.fit("▲ "..(reactor.outputLabel or recipe.output.label), 44), "info", "background")
  canvas:text(x + 44, y + 7, format.fit(format.amount(reactor.stock).." mB", 14, "right"), "text", "background")
  canvas:text(x + 58, y + 7, format.fit("output", 14, "right"), "muted", "background")

  for index = 1, 2 do
    local input = reactor.inputs[index]
    local fluid = recipe.inputs[index]

    if fluid then
      local rowY = y + 7 + index
      local tone = input and (input.missing and "bad" or "good") or "muted"

      canvas:text(x, rowY, format.fit("▼ "..(input and input.label or fluid.label), 44), "text", "background")
      canvas:text(x + 44, rowY, format.fit((input and format.amount(input.amount) or "-").." mB", 14, "right"), tone,
        "background")
      canvas:text(x + 58, rowY, format.fit((input and format.amount(input.required) or "-").." mB", 14, "right"), "muted",
        "background")
    end
  end
end

---@param canvas Canvas
---@param reactor Reactor
---@param x integer
---@param y integer
---@private
function View:renderControls(canvas, reactor, x, y)
  local settings = reactor.settings
  local valueX = x + 17

  canvas:text(x, y, "THRESHOLDS", "muted", "background")
  self:renderThreshold(canvas, reactor, "low", "Switch on below", x, y + 1)
  self:renderThreshold(canvas, reactor, "high", "Switch off at", x, y + 2)

  canvas:text(x, y + 3, "Step", "muted", "background")

  local stepOptions = {}

  for index, step in ipairs(self.app.config.steps) do
    stepOptions[index] = {
      label = (string.gsub(format.amount(step), "%.0+([kMGT]?)$", "%1")),
      action = function() self.stepIndex = index end
    }
  end

  canvas:segmented(valueX, y + 3, stepOptions, self.stepIndex)

  local auto = settings.mode == "auto"

  canvas:text(x, y + 5, "MODE", "muted", "background")

  local modeEnd = canvas:segmented(valueX, y + 5, {
    {label = "Auto", action = function() self:setMode(reactor, "auto") end},
    {label = "Manual", action = function() self:setMode(reactor, "manual") end}
  }, auto and 1 or 2)

  canvas:text(modeEnd + 2, y + 5,
    auto and "Program switches this reactor" or "Program never switches this reactor", "muted", "background")

  canvas:text(x, y + 7, "ENERGY", "muted", "background")

  local startup = reactor.recipe and reactor.recipe.startupEu or 0

  drawEnergyLevel(canvas, valueX, y + 7, 30, reactor.storedEu, reactor.capacity, startup)
  canvas:text(valueX + 32, y + 7, format.amount(reactor.storedEu).." / "..format.amount(reactor.capacity).." EU", "text",
    "background")

  local actionX = canvas:keyButton(valueX, y + 9, "R", "Recipe", function() self:openRecipe(reactor) end) + 1
  canvas:keyButton(actionX, y + 9, "N", "Rename", function() self:openRename(reactor) end)
end

---@param canvas Canvas
---@param reactor Reactor
---@param field "low"|"high"
---@param label string
---@param x integer
---@param y integer
---@private
function View:renderThreshold(canvas, reactor, field, label, x, y)
  local active = self.field == field
  local stepperX = x + 17
  local color = active and "selection" or "surfaceRaised"
  local signTone = active and "accent" or "muted"

  canvas:fill(x - 2, y, 1, 1, field == "low" and "markerLow" or "markerHigh")
  canvas:text(x, y, label, active and "accent" or "muted", "background")

  canvas:pill(stepperX, y, 18, color, "background")
  canvas:text(stepperX + 2, y, "-", signTone, color)
  canvas:text(stepperX + 4, y, format.fit(format.amount(reactor.settings[field]).." mB", 10, "center"), "text", color)
  canvas:text(stepperX + 15, y, "+", signTone, color)

  canvas:region(stepperX, y, 4, 1, function()
    self.field = field
    self:adjust(reactor, -1)
  end)
  canvas:region(stepperX + 4, y, 10, 1, function() self.field = field end)
  canvas:region(stepperX + 14, y, 4, 1, function()
    self.field = field
    self:adjust(reactor, 1)
  end)

  canvas:button(stepperX + 19, y, "Set", function() self:openThreshold(reactor, field) end, "raised")
end

---@param canvas Canvas
---@private
function View:renderEvents(canvas)
  local entries = self.app.memoryLog.entries

  drawSectionTitle(canvas, layout.eventsTitle, "EVENTS", #entries.." recent")

  self.eventsOffset = math.max(0, math.min(self.eventsOffset, #entries - layout.eventsRows))

  for row = 1, layout.eventsRows do
    local entry = entries[row + self.eventsOffset]

    if entry == nil then
      break
    end

    local y = layout.eventsTop + row - 1
    local style = levelStyles[entry.level] or levelStyles.info

    canvas:text(2, y, self.app.clock:format("%H:%M:%S", entry.time), "muted", "background")
    canvas:text(12, y, style[1], style[2], "background")
    canvas:text(19, y, format.fit(entry.message, canvas.width - 20), "text", "background")
  end
end

---@param canvas Canvas
---@private
function View:renderFooter(canvas)
  canvas:fill(1, layout.footer, canvas.width, 1, "surface")

  local x = 2

  for _, hint in ipairs(hints) do
    canvas:text(x, layout.footer, hint[1], "accent", "surface")
    x = x + unicode.len(hint[1]) + 1
    canvas:text(x, layout.footer, hint[2], "muted", "surface")
    x = x + unicode.len(hint[2]) + 3
  end
end

return View
