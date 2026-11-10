# TnT Raid Tools

Raid invite phrases and lead handoff, embedded in the raid manager panel.

## Layout

- `main.lua` - addon entry (OnLoad / OnUnload / OnSettingToggle)
- `core/constants.lua` - addon name, channel and match lists, panel sizes
- `core/settings.lua` - flat-key settings (`Get` / `Update` / `Is`), same pattern as WorldSatNav
- `features/raidtools.lua` - chat handling, invites, lead pass
- `ui/panel.lua` - Invite 1/2 windows beside the raid window, main panel window below it (raid window is never resized)
- `ui/listpanel.lua` - add/remove editor for a name array (blacklist, whitelist)
- `ui/widgets.lua` - widget factory, checkbox (ported from WorldSatNav), cleanup
- `features/raidsort.lua` - raid sort: tanks / healers / others into raid groups by gear score (see `constants.raidSort`)
- `core/sortplan.lua` - pure layout planning for the raid sort
- `core/authority.lua` - raid lead check; auto invites and raid sort pause when you are not lead in a raid of 2+
- `ui/sortwindow.lua` - raid sort window on the right of the raid window (Sort style toggle: 1 = role groups, 2 = 1 tank / 3 others / 1 healer per group)
- `logic.lua` - pure matching helpers
- `api.lua`, `API_DOCUMENTATION.md` - game API reference

## Settings

Stored under the addon folder name (`AAC-TnT-RaidTools`). Keys: `Invite1*`, `Invite2*`, `Lead*`.
Each invite has `Invite<N>Enabled`, `Invite<N>WhitelistEnabled`, `Invite<N>BlacklistEnabled`, `Invite<N>Phrase/Channel/Match`.
Name lists are arrays shared by both invites, one per raid type: `BlacklistPublic`, `BlacklistPrivate`, `WhitelistPublic`, `WhitelistPrivate`.
`Invite<N>BlacklistMode` / `Invite<N>WhitelistMode` (`public` | `private`) pick which shared list each invite uses.
`LeadWhitelist` is a comma-separated string.
