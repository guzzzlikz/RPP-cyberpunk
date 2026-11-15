# open77_quickhack

Cyberpunk 2077's scanner and quickhack interface on NativeUI, as a framework for server developers.

- **What the resource draws:**
  - the scanner vision, the target lock and the DATA / HACKING panel;
  - the `AVAILABLE QUICKHACKS` list and the Cyberdeck RAM bar;
  - the upload bar over the target and the warning the hacked player sees;
  - the game's own UI sounds.
- **What your resource decides:** which quickhacks exist, who may use them on what, what they cost,
  and what happens when one lands.

Full guide: [wiki/quickhack.md](../../../wiki/quickhack.md). Examples and ideas:
https://open2077.net/docs/quickhack-examples.

```lua
local qh = exports.open77_quickhack
qh:registerPreset("short_circuit", { canUse = "myCanUse", onExecute = "myExecute" })
qh:addTarget({ kind = "point", id = "terminal", position = { x = 0, y = 0, z = 0 }, name = "Terminal", tone = "device",
               quickhacks = { "short_circuit" } })
exports("myExecute", function(ctx) --[[ ctx.source, ctx.target, ctx.quickhack ]] end)
```

| Path | Content |
|---|---|
| `shared/config.lua` | Defaults: deck, keys, vision, the game's sound events, ranges |
| `shared/presets.lua` | The game's quickhacks (names, costs, timings) for `registerPreset` |
| `server/main.lua` | Authority: registry, targets, decks, scans, uploads, exports |
| `client/main.lua` | Input, target pick and anchors, net, vision, sounds |
| `client/ui.lua` | NativeUI presentation (motion, decode text, code rain) |
| `ui/quickhack.rml`, `ui/quickhack.rcss` | The document |
| `ui/icons/*.png` | Built-in icons, drawn by `tools/make_icons.py` (original line art) |
| `tests/` | Server rules without a host: `python tests/run.py` (lupa, Lua 5.4) |
