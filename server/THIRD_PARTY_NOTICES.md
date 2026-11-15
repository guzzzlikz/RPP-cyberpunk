# Third-party notices

## NanoSVG and libtess2 — native blip geometry

NanoSVG (unmodified), pinned to `239e102ec2c691f2902e20ace2ed36ee4a35cfe6`:
<https://github.com/memononen/nanosvg>. Open77 supplies its own restricted SVG
validator, flattening, stroke construction and native Ink adapter.

Copyright (c) 2013-14 Mikko Mononen memon@inside.org

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose, including
commercial applications, and to alter it and redistribute it freely, subject to
the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim
   that you wrote the original software. If you use this software in a product,
   an acknowledgment in the product documentation would be appreciated but is
   not required.
2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.

libtess2 (unmodified), pinned to `8dbd6483e920311a58c9af10a10beb278efebc36`:
<https://github.com/memononen/libtess2>.

SGI FREE SOFTWARE LICENSE B (Version 2.0, Sept. 18, 2008)
Copyright (C) [dates of first publication] Silicon Graphics, Inc.
All Rights Reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice including the dates of first publication and either
this permission notice or a reference to http://oss.sgi.com/projects/FreeB/
shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL SILICON
GRAPHICS, INC. BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN
AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Except as contained in this notice, the name of Silicon Graphics, Inc. shall
not be used in advertising or otherwise to promote the sale, use or other
dealings in this Software without prior written authorization from Silicon
Graphics, Inc.

## Cyber Engine Tweaks — Disable Boundary Teleport

Source: <https://github.com/maximegmd/CyberEngineTweaks/tree/9a8522f2a3d66729d971c48ae48f1053abfb5208>

Open77 adapts the `DisableBoundaryTeleportPatch` technique and its RED4ext
address hash for `game::WorldBoundarySystem::Tick`. Open77 adds a pinned 2.31
RVA/prologue check, conflict-safe ownership and unload restoration; it does not
redistribute Cyber Engine Tweaks binaries.

MIT License

Copyright (c) 2018 yamashi

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Cyber Engine Tweaks — TweakDB record name dictionary

Source: <https://github.com/maximegmd/CyberEngineTweaks/releases/tag/v1.37.1>

`client/src/world/VehicleRecordNames.cpp` carries the 1376 Cyberpunk 2077 2.31
vehicle record **names** (`Vehicle.*`) so the plugin can turn a runtime
TweakDBID back into the string the canonical registry needs. The names were
taken from the Cyber Engine Tweaks 1.37.1 TweakDB dictionary and then verified
one by one against the live 2.31 database; every id in the file recomputes from
its own name, which the build-time test re-checks. No Cyber Engine Tweaks code
or binary is used or redistributed — only the identifiers, which are facts about
the game's own database.

The MIT licence text above (Copyright (c) 2018 yamashi) covers this project.

## RemoveGangRetaliation

Source: <https://github.com/maojoejoe/RemoveGangRetaliation/tree/1d4b465be3a10994296e5c6bd3bff54abc1901e8>

**Open77 does not redistribute these files.** It vendors the two REDengine
tweak sources from commit `1d4b465be3a10994296e5c6bd3bff54abc1901e8` and
deploys them to a *developer's own* game install (`client/CMakeLists.txt`,
target `deploy-client`), but neither player-facing packager stages `r6/tweaks`:
not `scripts/package-client.ps1`, and not the mod publisher that produces the
signed `op77.mod.manifest/1` served to players. The live manifest carries zero
`r6/tweaks` entries. Players therefore run without this tweak; the runtime
`VehicleSpawnPolicy` (`client/src/Plugin.cpp`) culls network-identity-less
chase vehicles instead, so the effect is a degradation, not a break.

The tweaks prevent gang-retaliation chase vehicles and their occupants from
spawning. Provenance, runtime scope and removal paths are recorded in
`vendor/remove-gang-retaliation/UPSTREAM.md`.

The upstream repository did not include a license file when this revision was
integrated, so redistribution rights were never established. That is why the
mod stack packages this as an **optional, default-off** mod whose bytes come
from the author's own GitHub at the pinned commit (`distribution.mode` =
`origin`) rather than from `cdn.open2077.net`: nothing is rehosted, and the
player fetches it from upstream only after an explicit opt-in. Do not add
`r6/tweaks` back to a packager's copy list without first reviewing those
rights.

Consent matters here beyond licensing: these are **boot-time** tweaks, not
gated by `Open77MultiplayerPolicyActive()`. They alter the player's
singleplayer game and keep doing so after they quit Open77, until the files are
removed and the game restarted.

Cyberpunk 2077 and its game data remain copyright CD PROJEKT RED.

## Female pristine save (Nexus Mods 15918)

Source: <https://www.nexusmods.com/cyberpunk2077/mods/15918>

The `NCMP-Template-F` game save is the "UNMODDED-VANILLA Female Corpo Savegame
ACT II" produced and published by Shinetorli on Nexus Mods, used as the female
pristine world seed with only its metadata `name` changed. The page forbids
re-uploading it elsewhere and asks for permission before modifying or reusing
it: it is kept in this private repository for the project's own use, and must
not be published in a source archive or package without the author's
permission. File hashes and provenance are recorded in
`assets/pristine/README.md`. Cyberpunk 2077 and its game data remain copyright
CD PROJEKT RED.

It replaced on 2026-10-27 the `NCMP-Template-F` save produced and published by
NightCityMP/Tilted Phoques SRL
(<https://github.com/blyatiful1/NightCityMP/tree/3f3abc9060e443c7a3da1163fbd3c623197c1c10/code/assets/Saves/NCMP-Template-F>).

## Complete Third Person Overhaul (Nexus Mods 38266)

Source: <https://www.nexusmods.com/cyberpunk2077/mods/38266> (v1.2)

The third-person jump, air loop, fall loop, double jump and hard landing clips of the
`cyberm_jump_ma.anims`, `cyberm_jump_wa.anims` and `cyberm_female_wa.anims` banks are
derived from the animation sets of "Complete Third Person Overhaul" (CTO), used in
OPEN//77 with its author's permission (2026-11-15). They were resampled onto the
project's NPC rigs by `scripts/mirror/build-cto-jumps.py`; provenance and hashes are in
`assets/wolvenkit/cyberm/animations/cyberm_jump.anims.provenance.md` and
`cyberm_female_wa.anims.provenance.md`. The animations remain the work of the CTO
author; do not reuse them outside OPEN//77 without their permission. Cyberpunk 2077 and
its game data remain copyright CD PROJEKT RED.

## GameNetworkingSockets 1.5.1

Source: <https://github.com/ValveSoftware/GameNetworkingSockets/tree/v1.5.1>

Open77 épingle le commit `fa489fd2cb0fc86ef2503e330935d3eb03a6a064` et
redistribue `GameNetworkingSockets.dll` avec le client et le serveur. Le projet
est distribué sous licence BSD-3-Clause ; le texte complet est conservé dans
`server/native/licenses/GameNetworkingSockets.LICENSE`.

## Protocol Buffers 3.21.12

Source: <https://github.com/protocolbuffers/protobuf/tree/v3.21.12>

GameNetworkingSockets utilise la bibliothèque protobuf construite depuis le
commit `f0dc78d7e6e331b8c6bb2d5283e06aa26883ca7c`. Sa licence BSD-3-Clause est
conservée dans `server/native/licenses/protobuf.LICENSE`.

## Opus 1.5.2

Source: <https://github.com/xiph/opus/tree/v1.5.2>

Open77 épingle le commit `ddbe48383984d56acd9e1ab6a090c54ca6b735a6` et lie
Opus statiquement dans le client pour son codec vocal 48 kHz.

Copyright 2001-2023 Xiph.Org, Skype Limited, Octasic,
Jean-Marc Valin, Timothy B. Terriberry, CSIRO, Gregory Maxwell,
Mark Borgerding, Erik de Castro Lopo, Mozilla, Amazon

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

- Redistributions of source code must retain the above copyright notice,
  this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.
- Neither the name of Internet Society, IETF or IETF Trust, nor the names of
  specific contributors, may be used to endorse or promote products derived
  from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS ``AS IS''
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

Opus is subject to the royalty-free patent licenses listed by Xiph.Org at
<https://opus-codec.org/license/>.

## Lua 5.4.8

Source: <https://www.lua.org/ftp/lua-5.4.8.tar.gz>

Copyright © 1994–2025 Lua.org, PUC-Rio.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Chromium Embedded Framework 144.0.32

Source: <https://github.com/chromiumembedded/cef>

Open77 redistribue la distribution binaire standard CEF
`144.0.32+g5ce7d26+chromium-144.0.7559.258`. Sa licence BSD complète est copiée sans modification
dans `web/CEF-LICENSE.txt` à côté de `Open77.WebHost.exe`. Les composants Chromium et leurs notices
restent ceux de la distribution officielle épinglée ; aucun serveur Open77 ne peut remplacer ces
binaires natifs.

## KeraLua 1.4.9 et Lua 5.4 serveur

Source : <https://github.com/nlua/KeraLua/tree/06842dfec8929b0a6da51b3a053f6b87f03ae1c6>

Le serveur .NET utilise les bindings KeraLua sous licence MIT et leur runtime natif Lua 5.4.

## NSec.Cryptography 26.4.0 et libsodium 1.0.22

Sources : <https://github.com/ektrah/nsec> et <https://github.com/jedisct1/libsodium>

Le signataire de ressources Ed25519 utilise NSec et libsodium, distribués sous licences MIT et ISC.

## Monocypher 4.0.2

Source: <https://github.com/LoupVaillant/Monocypher/tree/4.0.2>

Le client natif utilise l'implémentation Ed25519 optionnelle de Monocypher pour
vérifier les générations de ressources signées par le serveur.

Copyright (c) 2017-2023, Loup Vaillant
Copyright (c) 2017-2019, Michael Savage
Copyright (c) 2017-2023, Fabio Scotoni
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## Lucide Static 1.47.0 (optional open77_icons resource)

Source: <https://github.com/lucide-icons/lucide>

The standalone `resources/standalone/open77_icons` package bundles 2,112 SVG
icons. Lucide is ISC-licensed; inherited Feather icons are MIT-licensed. The
complete upstream notices are included in that package's `LICENSE-LUCIDE.txt`
and must accompany redistribution. Browser class attributes are removed and
viewports padded for the native renderer; geometry is unchanged. Pinned source
integrity and per-asset hashes are recorded in `catalogue.json`.

## Dear ImGui 1.91.8

Source: <https://github.com/ocornut/imgui/tree/dbb5eeaadffb6a3ba6a60de1290312e5802dba5a>

The MIT License (MIT)

Copyright (c) 2014-2025 Omar Cornut

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Chakra Petch SemiBold and Rajdhani Medium (native nameplate faces)

Files: `client/assets/fonts/ChakraPetch-SemiBold.ttf`,
`client/assets/fonts/Rajdhani-Medium.ttf`, embedded in `Open77.dll` as
`RCDATA` resources and baked into the overlay font atlas by
`webui/WorldOverlay.cpp`. Unmodified copies of the faces the Open77 launcher
already ships (`launcher/src/Open77.Launcher/web/fonts`).

- Chakra Petch: Copyright 2018 The Chakra Petch Project Authors
  (<https://github.com/m4rc1e/Chakra-Petch.git>).
- Rajdhani: Copyright (c) 2014, Indian Type Foundry
  (<info@indiantypefoundry.com>).

Both are licensed under the SIL Open Font License, Version 1.1. The full
licence texts travel with the files as `client/assets/fonts/ChakraPetch-OFL.txt`
and `client/assets/fonts/Rajdhani-OFL.txt`. The fonts are not sold on their own.

## RmlUi 6.3 (NativeUI)

Source: <https://github.com/mikke89/RmlUi/tree/ba95ffe8> (Core, Layout,
Elements, FontEngineDefault, Debugger and the Win32 platform backend), built
as the static library `Open77.RmlUi` and linked into `Open77.dll`. Unmodified.
The Direct3D 12 renderer that draws it is Open77's own
(`client/src/nativeui/render`).

MIT License

Copyright (c) 2008-2014 CodePoint Ltd, Shift Technology Ltd, and contributors
Copyright (c) 2019-2026 The RmlUi Team, and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## FreeType 2.13.3 (NativeUI font rasterizer)

Source: <https://gitlab.freedesktop.org/freetype/freetype> at `42608f77`,
statically linked, unmodified. Used under the FreeType License (FTL); its full
text travels as `client/assets/nativeui/FreeType-FTL.txt`.

Portions of this software are copyright © 2024 The FreeType Project
(www.freetype.org). All rights reserved.

## Lato and Roboto Mono (NativeUI fonts)

The four `LatoLatin-*` and two `RobotoMono-*` (Regular, Bold) faces from
RmlUi's sample assets, embedded unmodified in `Open77.dll` as `RCDATA`.

- Lato: Copyright (c) 2010-2015, Łukasz Dziedzic (dziedzic@typoland.com),
  with Reserved Font Name Lato.
- Roboto Mono (<https://github.com/googlefonts/RobotoMono>): licensed as
  stated in RmlUi's sample asset notice, which names no separate holder.

Both are licensed under the SIL Open Font License, Version 1.1. The full
licence text travels as `client/assets/nativeui/RmlUi-sample-fonts-LICENSE.txt`.
The fonts are not sold on their own.

## SCRIPT//GO escrow (`scriptgo.dll`, `libscriptgo.so`, `ScriptGo.Escrow.dll`), SDK 0.1.7

Source: <https://github.com/scriptgo-hq/scriptgo-sdk/tree/v0.1.7> (`sdk/native`, `sdk/dotnet`)
(commit `00fc583733fa3b7d11cebae1d5c0f003e68e1b0f`)

Open77 redistributes files of `ScriptGo.Escrow.0.3.0.nupkg`, attached to the SDK release
`v0.1.7`, unmodified and pinned by SHA-256 in `vendor/scriptgo/scriptgo-native.json`
(`wiki/resource-escrow.md`):

- with the client, next to `Open77.dll`: `runtimes/win-x64/native/scriptgo.dll`, which asset
  escrow loads to decrypt escrowed preload archives;
- with the dedicated server, next to `Open77.Server` (with the Open77 adapter
  `Open77.Server.Escrow.ScriptGo.dll` built against it): `ScriptGo.Escrow.dll` and the native
  loader of the package's platform, `runtimes/win-x64/native/scriptgo.dll` or
  `runtimes/linux-x64/native/libscriptgo.so`, which run escrowed server scripts and hold asset
  keys.

The native loaders link libsodium and miniz statically (below); their notices also travel next to
them as `scriptgo.THIRD-PARTY-NOTICES.txt`, and this licence as `scriptgo-LICENSE.txt`.

MIT License

Copyright (c) 2026 SCRIPT//GO contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

### libsodium 1.0.22 (in `scriptgo.dll` and `libscriptgo.so`)

Source: <https://github.com/jedisct1/libsodium>

All the cryptography in the native loader: AES-256-GCM, X25519, HKDF-SHA256, Ed25519, SHA-256,
guarded and locked memory.

ISC License

Copyright (c) 2013-2026
Frank Denis <j at pureftpd dot org>

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

### miniz 3.1.0 (in `scriptgo.dll` and `libscriptgo.so`)

Source: <https://github.com/richgel999/miniz>

The inflater (tinfl) and CRC-32 used to read the zip inside an escrow payload.

Copyright 2013-2014 RAD Game Tools and Valve Software
Copyright 2010-2014 Rich Geldreich and Tenacious Software LLC

All Rights Reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
