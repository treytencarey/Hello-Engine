---
depends_on: [core/net, core/permission, core/player/attest, player, input, vault/microphone, sidebar/people]
conflicts_with: []
exposes: [voip, voip/frame, voip/participant, voip/silence, voip/silence/applied, voip/silenced, voip/heard, voip/mic, voip/intent, voip/participant/local, voip/indicator, voip/control]
---

# voip

Voice chat in a world. Each client speaks through root's microphone, which only root opens, and sends the packets root encodes on the world net. The server relays each participant's frames to the others, says who is speaking, and lets a user who may change the world's files silence another. Each client decodes the others' frames, per source. The server never decodes a frame.

## Turning voice on

A world turns voice on by spawning `voip` in its own boot, on the server:

```lua
commands:spawn({ voip = {} }):insert({ ChildOf = root })
```

A world that spawns no `voip` has no voice. `voip` is synced from the server, so its clients get it too. A world may set the Opus encoder's complexity root uses, a whole number from 0 to 10, on the carrier: `{ voip = { complexity = 5 } }`. It is 5 when absent.

## Components

- `voip = { complexity? }`: on the world's carrier. Its presence is voice in this world. Its removal takes every participant, the players' sync entries, the channel and, on each client, the ask of root, the push-to-talk key and the decoders.
- `voip/participant = { client_id, login, speaking, silenced }`: on each of this world's players, written by the server from the connection that owns the player (`core/net/owner`), and synced to everyone.
  - `client_id`: that connection's client id.
  - `login`: the GitHub login the connection's join ticket links (`core/player/attest.links.github`), while it is attested; absent otherwise. It is shown to everyone in the world.
  - `speaking`: true from a relayed frame of theirs until 300 ms after the last.
  - `silenced`: their connection carries `voip/silenced`.
  - A player another world shares here (`core/net/peer/mirror`), or one with no owner, is no participant; a player handed to another world stops being one.
- `voip/silence = { [<client id, as a string>] = true | false }`: on a player, written by its owner's client: `true` silences that participant, `false` unsilences them. Synced from the owner only (`{ authority = "client", target = "owner" }`); the server's half adds that entry to the player's `core/net/sync` with the participant's.

On the server, never synced:
- `voip/silence/applied = { [<client id, as a string>] = true | false }`: on the server's `core/net/connection` of a user allowed to silence, that user's `voip/silence` as the server last applied it, written whole after each one it applies. It goes with the connection, and with the mod when the last carrier goes.
- `voip/silenced = {}`: on the server's `core/net/connection` of a silenced user, added and removed by the server half. The participant's `silenced` says it.
- `voip/heard = { at }`: on the server's `core/net/connection`, the world's clock (seconds) when a frame of theirs was last stamped, at most every 100 ms.

On the client, never synced:
- `voip/mic = { muted, mode }`: on the local voice player (the participant this client owns), `{ muted = false, mode = "push" }` when it has none. `mode` is `"push"` (push-to-talk) or `"voice"` (open mic, gated by root's voice detection).
- `voip/intent = { transmit, listen, taken }`: on the local voice player. `transmit` is the ask open and root's reply `allowed`; `listen` that this player hears the others; `taken` the number of the newest packet taken from root's reply. A new player starts after the packets already on the reply.
- `voip/participant/local = { local_muted }`: on each remote participant's replica, `false` at first. A participant this player mutes is never decoded or played. The server never sees it.
- `voip/control = { kind }`: voip's marker on each of its items in the people panel's rows, beside `sidebar/people/row/item` (below).
- `voip/indicator = {}`: the speaking sphere, a child of a participant's replica while it is `speaking`, 1.4 m up. A headless world has no material assets, so there the marker comes and goes with nothing drawn.

## The channel: `voip/frame`

`voip` declares `voip/frame` on the world net's Unreliable lane (`core/net/channels.Unreliable`), on each side. A side that has not declared it drops its messages.

- **A client sends** `core/net/send { msg_type = "voip/frame", channel = "voip/frame", codec = 2, data }`: `data` is the frame as base64 text.
- **The server forwards** a frame read from `core/net/received` (this world net's own, by `net`) only when:
  - its sender's connection owns a participant here, is not an observer, and is not silenced;
  - it is well formed: `msg_type` is `"voip/frame"`, `codec` a number, `data` non-empty base64 text;
  - `data` is at most 2,048 bytes;
  - it is among its sender's first 4 frames of the relay's run.
- **It goes** to every other participant here who is not an observer, as `core/net/send_to_client`, with `from`, the sender's client id as core stamped it from the connection. A `from` the sender wrote is never passed on. An observer is sent no frame.

## The ask of root

Root alone opens the microphone (`vault/microphone`). Each client asks it once per world visit with `{ ["vault/microphone"] = { open, send, complexity }, Request = {} }`, a child of its copy of the carrier, unsynced, spawned once this client has a participant here. A respawned player keeps it, so one dialog covers the visit, and so does a reload of this mod. It goes with the carrier, or when `voip` leaves it.

- `open`: a participant here, not `muted`, not `silenced`. `false` closes the device, so the OS indicator goes off.
- `send`: `"voice"` in mode `"voice"`; otherwise `"all"` while V is held and `"none"` while it is not.
- `complexity`: the carrier's, or 5.
- It is written only on its inputs' edges: `voip/mic`, the participant, the talk action, the owner, the carrier and root's reply.

**Sending:** on the reply's change, in `Update` (a world's `First` systems never see a newly arrived reply), while the ask is open and root allowed it, each packet numbered above `taken` goes as one `core/net/send` on `voip/frame`, and `taken` becomes the reply's `last`. Packet `i` of `n` is number `last - n + i`. Packets older than root's window of 8 are lost, and the log says how many. With no microphone (`no_device`) nothing goes, and the player still hears.

**Push-to-talk:** `voip = { talk = { key = "KeyV" } }` in the local player's `input/game`, held: `input/game/voip/talk` is present while V is down. It is never bound in `input/ui`, where V types, and a mode switch removes the action, so opening a menu stops sending. It is bound again when `input` comes back, and unbound when the player stops being a participant.

**Receiving:** `core/net/received` on `voip/frame`, this world net's own (by `net`, as root's Lua messages reach every world VM). A frame from this player itself, from a participant this player muted, or from no participant here is dropped. Otherwise its `data` is decoded from base64 (`client/base64.lua`, this mod's own stateless file), the source's decoder opens on its first frame (`OpusDecoders`, key `tostring(from)`, 48 kHz mono), and its 960 samples are decoded and handed to playback. A participant gone takes its source and its decoder. A packet that does not decode is logged and dropped.

**Playback:** one speaker, `"voip/speaker"` in `Speakers`, opened (`{ rate = 48000 }`, the system's default device) while this player listens and removed when no one here does. With no `Speakers`, the player only speaks.
- **Each source's jitter buffer** holds its decoded 20 ms blocks, at most about a second (50 blocks; the oldest goes). A source starts playing once 3 blocks (60 ms) wait; one that runs dry primes again at 2, so a source whose arrival only just keeps up with playback still plays.
- **Mixing:** each frame, while the speaker holds less than 60 ms at its own rate (`queued()` against `status().sample_rate`), one block of every playing source is summed, clamped to 16 bits and written once. Silence is never written: a quiet speaker underruns. A block is resampled, linearly, only when the device plays at another rate than 48 kHz. A speaker still opening is written nothing.
- **Forget:** a participant gone drops its buffer and its decoder; one muted here drops its buffer.
- The buffers live in this half's Lua memory, not on components: they are audio, rewritten 50 times a second per source. A reload of this mod loses what they held, at most a second of speech, and they prime again within 60 ms.
- Measured on release, per 20 ms block: mixing 1 source about 55 µs, 2 sources about 72 µs, 4 sources about 123 µs; resampling 960 samples to 44.1 kHz about 125 µs.

## Who may silence

A user whose own connection's `core/permission/grants` name `"writer"`: someone the world's permission provider says may change its files. The server reads the grants on every `voip/silence` it applies, never anything the client sends, and ignores, with a log line, the entries of anyone else. A user never silences themself. Only the entries whose value differs from that user's `voip/silence/applied` are applied, so a user's standing entry never undoes another user's later change: if one silences a participant and another unsilences them, the first silencing someone else leaves that participant unsilenced. An entry taken out of the map changes nothing; unsilencing is a `false` entry.

The client knows whether to offer Silence from its own grants, which reach only that user's client (`core/permission`). Players never see who else may silence.

## In the people panel

voip adds its controls to `sidebar/people`'s rows as items: each a child of the row, holding `sidebar/people/row/item = { order, label, button, enabled }` and `voip/control = { kind }`. A row's player is its `sidebar/people/row/player.entity`, read through a declared query; a row whose player has no `voip/participant` gets no items.

| Row | Kind | Item | Shows |
|-----|------|------|-------|
| a remote participant's | `speaking` | text `*` (order 1) | lit while `speaking`, dimmed otherwise |
| | `mute` | button (order 2) | "Mute", or "Unmute" while this player mutes them (`voip/participant/local.local_muted`) |
| | `silence` | button (order 3), only while this client's own `core/permission/grants` name `"writer"` | "Silence", or "Unsilence" while the server says they are `silenced` |
| the local player's | `mic` | button (order 1) | "Mute mic", or "Unmute mic" while `voip/mic.muted` |
| | `level` | text (order 2) | the microphone's level from root's reply, as up to ten bars; empty while muted or not allowed |
| | `mode` | button (order 3) | "Push to talk (V)" in mode `"push"`, "Open mic" in mode `"voice"` |

- **Clicks** are voip's own `Pointer<Click>` observers on its buttons. Mute flips `local_muted`; Mute mic flips `voip/mic.muted`; the mode button switches `voip/mic.mode`; Silence writes that participant's entry into the local player's `voip/silence` (`true` to silence, `false` to unsilence, from their `silenced`), only while the grants name `"writer"`. A click on a dimmed button does nothing.
- **Labels follow the state**, never the click: Silence keeps its label until the server's `silenced` changes.
- **Items come on a row's `added` edge**, so a rebuilt row (the panel closing and opening, or rebuilding its scroll area) gets them again, showing the state as it stands. They are written again on the edges of what they show, and Silence comes and goes with the grants. The panel's rows take their items with them.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| First (server) | `voip/server` | Declares `voip/frame` on the world net when a carrier or the net arrives |
| First (server) | `voip/server` | The last carrier gone: the channel and the players' sync entries go |
| Update (server) | `voip/server` | Each player owned by a connection becomes a participant, rewritten on its owner, attestation and `voip/silenced` edges; adds the sync entries |
| Update (server) | `voip/server` | A player turned mirror, or that lost its owner, is no participant |
| Update (server) | `voip/server` | The relay, on `core/net/received`; stamps `voip/heard` |
| Update (server) | `voip/server` | Speaking on a `voip/heard` stamp |
| Update (server) | `voip/server` | Not speaking 300 ms after the last stamp; runs only while someone speaks |
| Update (server) | `voip/server` | Applies a writer's `voip/silence` entries that differ from `voip/silence/applied`, then writes it whole |
| First (client) | `voip/client` | Declares `voip/frame` on the world net when a carrier or the net arrives |
| First (client) | `voip/client` | The local voice player gets `voip/mic`, `voip/intent` and V; a remote participant gets `voip/participant/local` |
| First (client) | `voip/client` | A participant gone: its local state, key, source, decoder and sphere go |
| First (client) | `voip/client` | A carrier gone: its ask goes; the last one takes the channel, the key, the speaker, the buffers and the decoders |
| First (client) | `voip/client` | A participant muted here: its buffer goes |
| Update (client) | `voip/client` | The ask of root and the intent, on their inputs' edges |
| Update (client) | `voip/client` | Sends root's packets above `taken`, on the reply's change |
| Update (client) | `voip/client` | Receives, filters and decodes frames into each source's buffer, priming it |
| Update (client) | `voip/client` | Mixes the playing sources into the speaker while it holds under 60 ms; a per-frame drain, run only while a source plays |
| Update (client) | `voip/client` | Opens the speaker while this player listens, and removes it with the buffers when no one does |
| Update (client) | `voip/client` | The speaking sphere follows `speaking` |
| Update (client) | `voip/client` | voip's items in the people panel's rows: added on a new row, labels and Silence written on the edges of what they show |

## Use

```lua
-- the world's boot, on the server
commands:spawn({ voip = {} }):insert({ ChildOf = root })

-- a client silencing the participant with client id 7, on its own player
commands:entity(me):entry("voip/silence"):or_default():and_modify(function(s) s["7"] = true end)

-- a client muting a participant for itself only, on that participant's replica
row:get_mut("voip/participant/local").local_muted = true

-- the local player switching to open mic
row:get_mut("voip/mic").mode = "voice"

-- anything reading who speaks
Query[{ changed = { "voip/participant" } }]
```

## Notes

- The server never decodes a frame: it reads only its size and that it is base64 text.
- The relay's limits (2,048 bytes, 4 frames a run), the stamp's 100 ms and speaking's 300 ms are written where they are used.
- A participant is found from its connection through `core/net/owns`, so a player owned before its net declared ownership is a participant at once but sends and is silenced only once the connection lists it.
- Suites: `tests/test_voip_participants.lua`, `tests/test_voip_relay.lua` (one real client through core), `tests/test_voip_speaking.lua`, `tests/test_voip_silence.lua` (a stand-in permission provider; no git provider), `tests/test_base64.lua` (against a copy of root's encoder) and `tests/test_voip_client.lua` (a stand-in for root's reply, packets made with root's encoder, V through `input/synthetic_key`). The client suite opens the speaker itself on a device that does not exist: nothing plays it, so `queued()` counts every sample the mixer wrote, and the suite empties it between cases, as a device would. It needs no output device. Resampling runs only on a device at another rate, so no suite reaches it. `tests/test_voip_panel.lua` stands in for the people panel's rows, with the relationship declared as the panel declares it, and clicks with real `Pointer<Click>` events.
