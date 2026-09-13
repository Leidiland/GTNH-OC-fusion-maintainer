return {
  pollInterval = 5, -- Seconds between ME network checks
  stallTimeout = 60, -- Seconds a switched-on reactor may stay inactive before a warning, 0 disables

  network = {
    address = nil, -- ME interface or ME controller address, nil uses the first one found
  },

  reactors = {
    discover = true, -- Detect fusion controllers connected through adapters and MFUs
    addresses = {}, -- Controller addresses used in addition to detected ones
  },

  defaults = {
    lowThreshold = 100000, -- Switch-on amount in mB for newly detected reactors
    highThreshold = 1000000, -- Switch-off amount in mB for newly detected reactors
    inputBatches = 16, -- Recipe runs of each input required in the ME network before switching on
  },

  steps = {1000, 10000, 100000, 1000000, 10000000}, -- Threshold adjustment steps in mB

  log = {
    file = "fusion-maintainer.log", -- Log file in the program folder
    maxFileSize = 262144, -- Bytes before the log file is rotated
    timeZone = 0, -- Hours offset from UTC for timestamps
    discordWebhookUrl = "", -- Discord webhook for notifications, empty to disable
    discordLevel = "warning", -- Minimum level sent to Discord
  },

  customRecipes = { -- Recipes missing from the built-in table
    -- {
    --   output = {name = "plasma.helium", label = "Helium Plasma", amount = 125},
    --   inputs = {
    --     {name = "deuterium", label = "Deuterium", amount = 125},
    --     {name = "tritium", label = "Tritium", amount = 125}
    --   },
    --   startupEu = 40000000,
    --   eut = 4096,
    --   duration = 16
    -- },
  },
}
