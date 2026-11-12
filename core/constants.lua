-- TnT Raid Tools constants
local api = require("api")

local Constants = {
    addonName = "AAC-TnT-RaidTools", -- addon folder name, also the GetSettings id
    folderPath = api.baseDir .. "/AAC-TnT-RaidTools/",
    displayName = "TnT Raid Tools",
    version = "0.2.1",

    -- ---- invites / lead pass -------------------------------------------------------------------
    -- Chat channel id each selection matches; "*" matches any channel id.
    channels = {all = "*", nation = 6, faction = 14, guild = 7, whisper = -3, raid = 5},
    channelOrder = {"all", "nation", "faction", "guild", "whisper"}, -- order the button cycles through
    leadChannelOrder = {"whisper", "guild", "raid"}, -- lead pass only listens on these
    listModes = {"public", "private", "disabled"}, -- blacklist / whitelist mode per invite
    matches = {"equals", "includes", "starts"},

    -- ---- sounds --------------------------------------------------------------------------------
    buttonSound = "auction_put_up", -- click sound of the icon / checkbox buttons (a DING in AAC)
    -- Two sounds played together for an action (SetSounds keys).
    actionSounds = {
        expand = {"option", "mail"}, -- opening an invite card
        collapse = {"option", "skill_book"}, -- collapsing an invite card
        addInvite = {"store", "raid_team"}, -- the + button
    },

    -- ---- raid sort -----------------------------------------------------------------------------
    sortStyle = {class = 1, party = 2}, -- values of the RaidSortStyle setting
    sortStyles = {1, 2}, -- raid sort layouts the Style button cycles through
    sortStyleNames = {[1] = "Class", [2] = "Party"},
    raidSort = {
        -- Class style: tanks / healers / everyone else are placed in these raid groups (5 slots each).
        -- A class in both class lists counts as a tank (tank list is checked first).
        tankGroups = {1, 6},
        healerGroups = {5, 10},
        otherGroups = {2, 3, 4, 7, 8, 9},
        groupSize = 5,
        maxMembers = 50,

        -- timings
        recheckMs = 10000, -- re-read the raid this often (picks up gear scores of people now in range)
        settleMs = 3000, -- wait this long after someone joins/leaves before sorting; every further join/leave restarts the wait
        sendDelayMs = 40, -- wait this long between planning a move and sending it
        moveDelayMs = 250, -- wait after sending a move before checking that it took effect
        pollMs = 125, -- how often to check while waiting for a move to show up in the roster
        moveTimeoutMs = 4000, -- a move that has not shown up after this long counts as failed
        maxRetries = 3, -- failed moves in a row (while you are lead) re-planned before giving up and stopping
        maxMovesPerRun = 120, -- safety cap for one sorting run

        -- Role detection. A class in tankClasses / healerClasses decides the role directly.
        tankClasses = {"Skullknight", "Nightcloak", "Dreambreaker", "Abolisher", "Templar", "Hexblade"},
        healerClasses = {"Confessor", "Cleric", "Hierophant", "Templar", "Soothsayer", "Edgewalker"},
        -- A class that is in neither list is matched by its skillsets instead (read from the player's own
        -- three skillset ids): a tank skillset makes a tank; else a healer skillset makes a healer unless
        -- the player also has one of the excluded skillsets (damage specs).
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
        -- Last resort for a player whose class and skillsets cannot be read: the role colour they set in
        -- the raid window. Maps the id Team:GetRole returns to "tank" / "healer" / "other". The ids are
        -- logged as color=<id> in the raid sort trace; an id not listed here is ignored.
        roleColors = {[0] = "other", [1] = "tank", [2] = "healer", [3] = "other"}, -- 0 blue, 1 green, 2 pink, 3 red

        -- Class style: "others" are sub-sorted by the first skillset in this list that they have (earlier =
        -- higher up, filling from the first other group), then by gear score. Others with none of them come last.
        otherSkillsetOrder = {"Sorcery", "Archery", "Battlerage"},
        gapBetweenRoles = true, -- leave one empty group between those skillset buckets when the raid has room

        -- "Save GS+Class" writes one small file per player (name, className, gearScore) to this folder
        -- (relative to the addons folder) and reads it back for a player whose class or gear score
        -- cannot be read right now.
        playersFolder = "AAC-TnT-RaidTools/players",

        -- Test only (see features/raidsort_debug.lua). While enabled, turning the raid sort on does NOT
        -- sort. It writes one file per raid member to playersFolder with their class name, their three
        -- skillset ids and names, and the raw unit info, so skillset names can be checked against the game.
        dump = {enabled = false},
        -- Test only: while enabled, turning the raid sort on moves `name` to each of `slots` in turn and
        -- logs where they actually land (and who was in the way). No sorting happens while on.
        probe = {enabled = false, name = "Madpeter", slots = {1, 6, 11}},
    },

    -- ---- AFK guess -----------------------------------------------------------------------------
    -- The game exposes no AFK flag, so you count as AFK when your world position stays put.
    -- Every intervalMs your position is compared with the previous one; staying within `tolerance` on
    -- x, y and z adds a point, any bigger move resets the points. The AFK limit is the chosen number of
    -- minutes (setting AfkMinutes, one of minuteOptions) converted to points.
    afk = {intervalMs = 5000, tolerance = 1, minuteOptions = {2, 5, 10}},

    -- ---- UI layout -----------------------------------------------------------------------------
    -- Window below the raid window: the main panel (mainHeight) and the list editors that replace
    -- it while open (editorHeight). The raid window itself is never resized.
    panel = {width = 600, mainHeight = 228, editorHeight = 360, gap = 4},
    -- Raid sort window on the right side of the raid window
    sortPanel = {width = 300, height = 252, headerHeight = 36, gap = 4},
    -- Invite list window on the left side of the raid window: a header, then a scrolling stack of invite cards.
    -- A card is a header row (collapse checkbox, title, X) plus a body that is hidden when collapsed.
    invitePanel = {
        width = 300, height = 420, headerHeight = 30, gap = 4,
        cardHeaderHeight = 36, cardBodyHeight = 126, cardGap = 4, scrollWidth = 18,
    },
}

return Constants
