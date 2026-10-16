# Credits

AzerothTrail builds on the work of others. Thank you to everyone below.

## Data sources

| Project | License | Used for |
| --- | --- | --- |
| [SimpleArmory](https://github.com/kevinclement/SimpleArmory) | MIT | Route and mount data |
| [Rarity](https://github.com/WowRarity/Rarity) | GPL-2.0 | Drop rates, quest IDs, coordinates |

## Libraries

The libraries below are bundled unmodified under `Libs/` and loaded through `embeds.xml`.

| Library | Source | Version | License |
| --- | --- | --- | --- |
| LibStub, CallbackHandler-1.0, AceAddon-3.0, AceDB-3.0, AceConsole-3.0, AceEvent-3.0 | [Ace3](https://github.com/WoWUIDev/Ace3) | tag `Release-r1403`, commit `d295b12f8b889a30e86e0e901c5494df4b149c49` | Ace3 BSD-style license, copy at `Libs/LICENSE-Ace3.txt` (LibStub's own header places it in the public domain) |
| LibDataBroker-1.1 | [tekkub/libdatabroker-1-1](https://github.com/tekkub/libdatabroker-1-1) | tag `v1.1.4`, commit `1a63ede0248c11aa1ee415187c1f9c9489ce3e02` | No license file or header upstream; bundled as a standard LDB library (see note below) |
| LibDBIcon-1.0 | [CurseForge: libdbicon-1-0](https://www.curseforge.com/wow/addons/libdbicon-1-0) (author Funkeh/funkydude, no official GitHub repo) | `v12.1.1` (CurseForge file 9119909, svn r165, `LibDBIcon-1.0.lua` MINOR 57) | CurseForge lists "Ace3 Style BSD"; the library's .toc says `X-License: All Rights Reserved` (see note below) |

Notes:

- LibDBIcon-1.0 states conflicting licenses (CurseForge page vs its own .toc) and ships no license file. It is a standard, widely embedded library; if the author objects it can be removed, since the minimap button is optional.
- LibDataBroker-1.1 has no stated license upstream. Same caveat as above.
- Ace3 libraries not listed above (AceGUI, AceConfig, and so on) are deliberately not included.

## Optional integrations

- [TomTom](https://www.curseforge.com/wow/addons/tomtom) by jnwhiteh: optional waypoint integration, not bundled. Licensed "All Rights Reserved" per its CurseForge page; the integration calls its public API only, no code copied.
