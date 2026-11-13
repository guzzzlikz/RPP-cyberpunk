# open77_shell

This resource is the connection screen players see while they join a server: it shows the
connection, download and loading progress, lets the player cancel, and offers Retry
connection, Return to launcher and Quit game when something goes wrong. A failed connection also shows a support
code and a report the player can copy.

- **Docs:** [The OPEN//77 launcher](https://open2077.net/docs/launcher), [Custom loading screens](https://open2077.net/docs/loading-screens)
- **Starts:** on its own
- **Needs:** nothing
- **Runs on:** client

It is the trusted client bootstrap, not a downloadable gamemode menu. The launcher owns server
selection, history, direct connect and mod consent. This resource displays connection progress
and recovery without maintaining another directory.

The screen is a NativeUI document (`ui/shell.rml`, `ui/shell.rcss`, driven by `client/ui.lua`),
drawn by the game's own renderer: no browser. The first time it opens in a game run, an intro
plays: OPEN//77 lands over one of the artworks (chromatic ghosts converging, a flash, a few
glitch tears), then cross-fades into the screen, which assembles block by block. A click or a key
skips it. The backdrop is a slideshow of four artworks (`ui/art/`), each slowly pushing in and
cross-fading to the next; the headline glitches now and then. It follows the October 2026
website/launcher identity: the white/yellow wordmark, wide
italic Druk headings, Nippo labels, Satoshi body text, angled controls and pink recovery actions,
with every panel frosting the city behind it (glass). Views and steps animate with springs.
Artwork and fonts are bundled under `ui/` (`ui/SOURCES.txt`); rendering never needs the website.
While a connection runs (identity, handshake, downloads) the screen keeps the cursor, so Cancel
and Back to launcher stay clickable; it lets go when the world starts streaming. The current phase has its own real progress bar, followed
by five connection checkpoints. Indeterminate stages have no invented percentage, and 100%
does not dismiss the cover before the native world handoff. A server's optional accent colors
the progress rail; the platform identity remains consistent.
The default screen stays visible through the native menu unmount until the loading
handoff completes. A server-provided loadscreen (a WebUI page, unchanged) still takes over
during streaming: NativeUI draws above WebUI, so the built-in screen fades out once that page
has had a moment to paint, and comes back if it is unmounted.

Lobby audio is an owned local MP3 at `audio/lobby.mp3`, played through Open77's own audio
(`Play2DSound`, no browser), looping at 12% by default.
The footer dock persists
pause/volume as one `lobby:music` JSON value in this trusted resource's device-local KVP.
It is paused whenever the shell is hidden or a custom loadscreen takes over.

`tests/connection_test.lua` (run by the server test suite) covers the controller and
`tests/ui.test.lua` the screen's error explanations, sanitising and address privacy.
