# TnT Raid Tools

An ArcheAge Classic addon that helps the raid leader run a raid from the raid manager window. It has three tools:

1. **Auto invites** - invite anyone who types a keyword in chat.
2. **Lead pass** - hand raid lead to whoever types a keyword.
3. **Raid sort** - keep the raid ordered into tank / healer / other groups by gear score.

Everything is built into the raid manager: a settings panel under the raid window, an invite list on its left, and the raid sort window on its right. The raid window itself is never resized or changed. Opening the addon's settings button shows the panel.

## Auto invites

Anyone who says an invite keyword in chat is invited to the raid.

- Press **+** in the top left of the raid window to add an invite. **X** deletes it, the arrow icon collapses or expands its card, and **Zzz** switches that one invite off without deleting it.
- Each invite has:
  - **Phrase** - the keyword.
  - **Channel** - `all`, `nation`, `faction`, `guild` or `whisper`.
  - **Match** - `equals` (whole message), `includes` (anywhere in the message) or `starts` (message begins with it).
  - **Blacklist mode** and **Whitelist mode** - `public`, `private` or `disabled`.
- There is no limit on the number of invites. If a message matches more than one, only one invite is sent.
- The **INVITES Enabled** checkbox in the main panel is a global switch for every invite. Turning it off keeps the list.
- Players already in the raid are skipped.

### Name lists

There are two shared lists, each in a **public** and a **private** version (four in total): the **blacklist** (these players are never invited) and the **whitelist** (only these players are invited). Each invite picks which version of each list it uses, or `disabled` to ignore that list. Use the BLACKLIST / WHITELIST buttons in the main panel to add or remove names.

## Lead pass

When someone types the lead keyword (default `lead`, exact match) on the chosen channel (`whisper`, `guild` or `raid`), they must be in the raid and they are made raid leader. Tick **Only listed names** and use **EDIT LIST** to limit this to specific players. Off by default.

## Raid sort

Turn it on with the **Enabled** checkbox in the Raid Sort window (off by default). The window collapses to a header bar while it is off.

The addon reads everyone in the raid, plans the ideal layout and moves one member at a time, confirming each move in the roster before planning the next. The raid is re-checked every 10 seconds (gear scores and classes can only be read while a member is in range) and a few seconds after anyone joins or leaves. Within a role, players are sorted by gear score, highest first.

### Save GS+Class

Tick **Save GS+Class** in the Raid Sort window (off by default) to keep each player's real gear score and class on disk. Whenever a member is in range and can be read, their values are written to `AAC-TnT-RaidTools/players/<name>.dat` (only when they changed). Before sorting, a player whose class or gear score cannot be read and is not cached in memory is looked up in that folder, so people out of range (or after a reload) are still sorted by their last known values instead of last.

### Role detection

A player's role is decided in this order:

1. Their class, from the tank and healer class lists in `core/constants.lua`.
2. Their three skillsets: a Defense skillset makes a tank, a Vitalism skillset makes a healer (unless they also have Battlerage, Archery or Sorcery). Everyone else is an "other".
3. As a last resort, the role colour set in the raid window.

### Sort styles

The **Sort style** button switches between two layouts:

- **Party** (default): every group is 1 tank, 3 others and 1 healer, top to bottom. Group 1 gets the highest gear score of each role. A group with no tank gets an extra other instead. A short group keeps its healer in the bottom slot.
- **Class**: tanks go in groups 1 and 6, healers in groups 5 and 10, and everyone else in groups 2, 3, 4, 7, 8 and 9. Others are further grouped by skillset (Sorcery, then Archery, then Battlerage, then everything else), with an empty group between each when there is room.

Slot layout and timings (settle time, retries, move limits) are all in `core/constants.lua` under `raidSort`.

## Raid lead requirement

Auto invites and raid sort both need raid lead, so they pause (your settings are untouched) while you are in a raid of 2 or more without lead, and resume when you get it. Alone you are always allowed, since inviting someone is what makes you leader. The raid sort window shows a notice when it is paused, and a chat message is written when the state changes.

## Settings

Saved under the addon folder name (`AAC-TnT-RaidTools`) using flat keys.

| Key | Meaning |
| --- | --- |
| `Invites` | List of `{Phrase, Channel, Match, BlacklistMode, WhitelistMode, Collapsed, Active}` |
| `InvitesEnabled` | Global on/off for all invites |
| `BlacklistPublic`, `BlacklistPrivate`, `WhitelistPublic`, `WhitelistPrivate` | The shared name lists |
| `LeadEnabled`, `LeadPhrase`, `LeadChannel` | Lead pass switch, keyword and channel |
| `LeadWhitelistEnabled`, `LeadWhitelist` | Restrict lead pass to a list of names |
| `RaidSortEnabled` | Raid sort on/off |
| `RaidSortStyle` | `2` = Party (default), `1` = Class |
| `DebugChat` | Extra debug tracing |

Older `Invite1*` / `Invite2*` settings are migrated into the `Invites` list on load (enabled ones only).

## Debugging

Whisper `/debug` to yourself to toggle debug logging. While it is on, the addon writes a rolling trace (last 150 lines) of chat events, invite checks, authority changes and raid sort moves to `debug.lua` in the addon folder. Nothing is written while it is off.

## Credits

Author: Wasbeerotb. The game API reference is in `API_DOCUMENTATION.md`.
