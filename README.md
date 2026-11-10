# TnT Raid Tools

Raid invite phrases and lead handoff, embedded in the raid manager panel.

## Layout

- `main.lua` - addon entry (OnLoad / OnUnload / OnSettingToggle)
- `core/constants.lua` - addon name, channel and match lists, panel sizes
- `core/settings.lua` - flat-key settings (`Get` / `Update` / `Is`), same pattern as WorldSatNav
- `features/raidtools.lua` - chat handling, invites, lead pass
- `ui/panel.lua` - main panel window below the raid window (raid window is never resized)
- `ui/invitelist.lua` - scrolling list of invites left of the raid window; "+" in the raid panel's top left adds one, X deletes, the arrow icon collapses / expands it
- `ui/listpanel.lua` - add/remove editor for a name array (blacklist, whitelist)
- `ui/widgets.lua` - widget factory, checkbox (ported from WorldSatNav), cleanup
- `features/raidsort.lua` - raid sort: tanks / healers / others into raid groups by gear score (see `constants.raidSort`)
- `core/sortplan.lua` - pure layout planning for the raid sort
- `core/authority.lua` - raid lead check; auto invites and raid sort pause when you are not lead in a raid of 2+
- `ui/sortwindow.lua` - raid sort window on the right of the raid window (Sort style toggle: 1 = role groups, 2 = 1 tank / 3 others / 1 healer per group)
- `logic.lua` - pure matching helpers
- `api.lua`, `API_DOCUMENTATION.md` - game API reference

## Settings

Stored under the addon folder name (`AAC-TnT-RaidTools`). Keys: `Invites`, `Lead*`.
`InvitesEnabled` is the global on/off for all invites. Invites is a list of `{Phrase, Channel, Match, BlacklistMode, WhitelistMode, Collapsed}` (no limit; older `Invite1*` / `Invite2*` settings are migrated, enabled ones only).
Name lists are arrays shared by both invites, one per raid type: `BlacklistPublic`, `BlacklistPrivate`, `WhitelistPublic`, `WhitelistPrivate`.
`BlacklistMode` / `WhitelistMode` (`public` | `private` | `disabled`) pick which shared list each invite uses.
`LeadWhitelist` is a comma-separated string.
