---@class Fluid
---@field name string
---@field label string
---@field amount integer

---@class Recipe
---@field id string
---@field output Fluid
---@field inputs Fluid[]
---@field startupEu integer
---@field eut integer
---@field duration integer
---@field custom boolean
---@field search string

---@class RecipeBook
local RecipeBook = {}
RecipeBook.__index = RecipeBook

---@return Fluid
local function normalizeFluid(fluid)
  return {name = fluid.name, label = fluid.label or fluid.name, amount = fluid.amount or 0}
end

---@return Recipe
local function normalizeRecipe(data, custom)
  local recipe = {
    output = normalizeFluid(data.output),
    inputs = {},
    startupEu = data.startupEu or 0,
    eut = data.eut or 0,
    duration = data.duration or 0,
    custom = custom
  }

  local names = {}
  local words = {recipe.output.label, recipe.output.name}

  for _, input in ipairs(data.inputs or {}) do
    local fluid = normalizeFluid(input)
    table.insert(recipe.inputs, fluid)
    table.insert(names, fluid.name)
    table.insert(words, fluid.label)
    table.insert(words, fluid.name)
  end

  table.sort(names)

  recipe.id = recipe.output.name.."<"..table.concat(names, "+")
  recipe.search = string.lower(table.concat(words, " "))

  return recipe
end

---Create a recipe book from built-in and custom recipes
---@param recipes table[]
---@param customRecipes? table[]
---@return RecipeBook
function RecipeBook.new(recipes, customRecipes)
  local self = setmetatable({list = {}, byId = {}}, RecipeBook)

  for _, data in ipairs(recipes) do
    self:add(normalizeRecipe(data, false))
  end

  for _, data in ipairs(customRecipes or {}) do
    self:add(normalizeRecipe(data, true))
  end

  table.sort(self.list, function(a, b)
    if a.output.label ~= b.output.label then
      return a.output.label < b.output.label
    end

    return a.startupEu < b.startupEu
  end)

  return self
end

---@param recipe Recipe
---@private
function RecipeBook:add(recipe)
  local existing = self.byId[recipe.id]

  if existing and recipe.custom then
    for index, entry in ipairs(self.list) do
      if entry == existing then
        self.list[index] = recipe
      end
    end
  else
    local baseId, suffix = recipe.id, 2

    while self.byId[recipe.id] do
      recipe.id = baseId.."#"..suffix
      suffix = suffix + 1
    end

    table.insert(self.list, recipe)
  end

  self.byId[recipe.id] = recipe
end

---@param id string|nil
---@return Recipe|nil
function RecipeBook:get(id)
  return id and self.byId[id] or nil
end

---Recipes matching a query against fluid names and labels
---@param query string
---@return Recipe[]
function RecipeBook:search(query)
  query = string.lower(query or "")

  if query == "" then
    return self.list
  end

  local result = {}

  for _, recipe in ipairs(self.list) do
    if string.find(recipe.search, query, 1, true) then
      table.insert(result, recipe)
    end
  end

  return result
end

return RecipeBook
