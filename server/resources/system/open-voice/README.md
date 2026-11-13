# open-voice

This resource gives players three voice ranges (whisper, normal and shout) that they cycle with F11, and a small HUD line that shows the active range and whether they are talking.
`open-voice` is a compact, pma-voice-inspired reach-mode companion for the
native OPEN//77 voice stack. It depends on `open77_voice`, which remains the
only owner of microphone capture, PTT/VAD, Opus, routing, playback and network
media. This package never reads PCM/Opus and never calls `setTransmitting`.

- **Docs:** [Integrated voice chat](https://open2077.net/docs/voice)
- **Starts:** on its own
- **Needs:** `open77_voice`
- **Runs on:** server and client

## Defaults

The server owns and validates every mode in `server/config.lua`:

| Mode | Distance |
|---|---:|
| `whisper` | 3 m |
| `normal` | 20 m |
| `shout` | 40 m |

F11 cycles the modes by sending `open-voice:cycle` to the authenticated server.
The server rate-limits the request, chooses the next mode from its own current
state, and applies it through `Open77.voice.setProximity`. The client never sends
or applies an arbitrary distance. Names, labels, colors, distances, default mode,
key and cooldown are checked at server resource load; invalid configuration
fails the resource rather than silently weakening policy.

Supported cycle keys are A-Z, 0-9, F1-F12, SPACE, ENTER/RETURN and the arrow
keys. Input is ignored while another WebUI captures the keyboard.

## HUD states

The HUD is a NativeUI document (`ui/voice.rml`, `ui/voice.rcss`) drawn by the
game's renderer, with no browser page. It is one compact line in the
bottom-right corner, turned slightly toward the centre of the screen like the
other HUD wings, with no panel or background:

- a status line: the state in words and the activation (`PTT` or `VAD`), then a
  beating "heard" counter that only appears while someone is audible;
- a skewed mic badge tinted by state; it fills and sends out rings while you talk;
- a twelve-segment input meter (the last two segments amber and red);
- the active range in its colour, its distance, and one pip per preset up to the active one;
- the cycle key as a keycap.

States: `idle` (grey), `detected` (cyan), `talking` (mint, filled mic, rings),
`muted` (red, slashed mic, meter dark), `offline` (dim, slashed). A new range
drops in with a spring. A server rejection shows as a red strip above the line
for a few seconds. The line steps aside while another interface holds the
cursor, and `setHudVisible(false)` hides it.

`client/ui.lua` is the presentation layer and a small example of NativeUI: one
data model (`voice`) filled from the payload `client/main.lua` builds, only the
changed values merged into the document, `ui:animate` springs on a range
change, and a light camera float through `ui:projection`. `tests/ui.test.lua`
covers the model and the document updates
(Lua 5.4, from the repository root).

## Client integration

Other client packages can call `getState()`, `getModes()`, `requestCycle()` and
`setHudVisible(visible)` through `Open77.exports.call("open-voice", ...)`.
`open-voice:modeChanged(mode, distance, label, color)` is emitted locally after
each canonical server response. `open-voice:cycle` and
`open-voice:setHudVisible` are equivalent local events. None of these APIs can
submit an arbitrary distance; reach remains server-owned.

Trusted server packages can emit
`open-voice:setPlayerMode(playerId, modeName)` or
`open-voice:cyclePlayerMode(playerId)`. After a canonical application,
`open-voice:modeApplied(playerId, modeName, distance, label, color)` is emitted
locally on the server. These are local events, not registered network events.
