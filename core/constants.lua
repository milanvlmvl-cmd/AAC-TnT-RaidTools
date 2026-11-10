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
    -- Raid sort: tanks / healers / everyone else are placed in these raid groups (5 slots each).
    -- A class in both lists counts as a tank (tank list is checked first).
    raidSort = {
        tankGroups = {1, 6},
        healerGroups = {5, 10},
        otherGroups = {2, 3, 4, 7, 8, 9},
        groupSize = 5,
        maxMembers = 50,
        recheckMs = 10000, -- re-read the raid this often (picks up gear scores of people now in range)
        settleMs = 1500, -- wait this long after someone joins/leaves before sorting
        moveDelayMs = 250, -- wait after sending a move before checking that it took effect
        pollMs = 125, -- how often to check while waiting for a move to show up in the roster
        moveTimeoutMs = 4000, -- give up (and stop) if a move still has not shown up after this long
        maxMovesPerRun = 120, -- safety cap for one sorting run
        -- Test only: when enabled, turning the raid sort on moves `name` to each of `slots` in turn
        -- and logs where they actually land (and who was in the way). No sorting happens while on.
        -- Test only: while enabled, turning the raid sort on does NOT sort. It writes one file per raid
        -- member to `folder` (relative to the addons folder) with their class name, their three skillset
        -- ids and names, and the raw unit info, so skillset names can be checked against the game.
        dump = {enabled = false, folder = "AAC-TnT-RaidTools/players"},
        probe = {enabled = false, name = "Madpeter", slots = {1, 6, 11}},
        -- A class that is in neither list below is matched by its skillsets instead (read from the
        -- player's own three skillset ids): a tank skillset makes a tank; else a healer skillset makes
        -- a healer unless the player also has one of the excluded skillsets (damage specs).
        tankSkillsets = {"Defense"},
        healerSkillsets = {"Vitalism"},
        healerExcludedSkillsets = {"Battlerage", "Archery", "Sorcery"},
        -- The game's GetSkillsetNameById returns internal names. Lookup to the names players know.
        -- Confirmed against dumped players: fight, illusion, adamant, will, magic, romance, vocation.
        -- death, wild, love are assumed (Occultism, Archery, Vitalism); predator and trooper unknown.
        skillsetDisplayNames = {
            fight = "Battlerage", illusion = "Witchcraft", adamant = "Defense", will = "Auramancy",
            death = "Occultism", wild = "Archery", magic = "Sorcery", vocation = "Shadowplay",
            romance = "Songcraft", love = "Vitalism",
        },
        -- "Others" are sub-sorted by the first skillset in this list that they have (earlier = higher up,
        -- filling from the first other group), then by gear score. Others with none of them come last.
        gapBetweenRoles = true, -- leave one empty group between those skillset buckets when the raid has room
        otherSkillsetOrder = {"Sorcery", "Archery", "Battlerage"},
        tankClasses = {"Skullknight", "Nightcloak", "Dreambreaker", "Abolisher", "Templar", "Hexblade"},
        healerClasses = {"Confessor", "Cleric", "Hierophant", "Templar", "Soothsayer", "Edgewalker"},
    },
    -- Raid sort window on the right side of the raid window
    sortPanel = {width = 300, height = 190, headerHeight = 36, gap = 4},
    -- Invite 1 / Invite 2 windows hung off the left / right edge of the raid window
    invitePanel = {width = 300, height = 162, headerHeight = 36, gap = 4},
}

return Constants
