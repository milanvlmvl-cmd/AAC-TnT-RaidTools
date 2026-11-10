-- TnT Raid Tools constants
local api = require("api")

local Constants = {
    addonName = "AAC-TnT-RaidTools", -- addon folder name, also the GetSettings id
    folderPath = api.baseDir .. "/AAC-TnT-RaidTools/",
    displayName = "TnT Raid Tools",
    version = "0.1.0",
    inviteSlots = 2,
    -- Chat channel id each selection matches; "*" matches any channel id.
    channels = {all = "*", nation = 6, faction = 14, guild = 7, whisper = -3, raid = 5},
    channelOrder = {"all", "nation", "faction", "guild", "whisper"}, -- order the button cycles through
    leadChannelOrder = {"whisper", "guild", "raid"}, -- lead pass only listens on these
    listModes = {"public", "private", "disabled"}, -- blacklist / whitelist mode per invite
    matches = {"equals", "includes", "starts"},
    -- Window below the raid window: the main panel (mainHeight) and the list editors that replace
    -- it while open (editorHeight). The raid window itself is never resized.
    panel = {width = 600, mainHeight = 180, editorHeight = 360, gap = 4},
    -- Invite 1 / Invite 2 windows hung off the left / right edge of the raid window
    invitePanel = {width = 300, height = 162, headerHeight = 36, gap = 4},
}

return Constants
