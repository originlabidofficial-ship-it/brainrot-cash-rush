[![make.fun - roblox-brainrot-01](https://make.fun/badge/roblox-brainrot-01.svg)](https://make.fun/bounty/roblox-brainrot-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)
[![rank](https://make.fun/badge/roblox-brainrot-01/originlabidofficial-ship-it/brainrot-cash-rush/rank.svg)](https://make.fun/bounty/roblox-brainrot-01/leaderboard?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)
[![reward](https://make.fun/badge/roblox-brainrot-01/originlabidofficial-ship-it/brainrot-cash-rush/reward.svg)](https://make.fun/bounty/roblox-brainrot-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)

# Brainrot Cash Rush

A complete 3D brainrot economy on Roblox. Grab one of **22 original creatures** from the
wild, carry up to your backpack cap, bank them in a ring of display slots on your own
neon pad, and earn cash every second. Spend that cash on six five-level upgrades, discover
every species in the Index, complete three rotating quests, steal from unprotected rivals,
survive the **Brainrot Wave every 90 seconds**, and rebirth at **$500** for a permanent
**+25%** multiplier.

**Play it:** https://www.roblox.com/games/97556431659360 - a Public Roblox experience, free to join.

## The first minute

1. You appear at the neon spawn portal at the south end of the plaza. The onboarding
   overlay lists five live objectives: **move, grab, bank, open the Index, rebirth**.
2. Walk north into the raised **Wild Zone**. Eight creatures are already roaming; more
   spawn every 5 seconds, weighted by rarity. Touch one to grab it (base carry cap: 3).
3. Run back to your glowing base deck. Standing on it banks every carried creature into a
   free display slot; each one pays its rarity income every second, multiplied by your
   rebirth bonus and Income upgrade.
4. Press **E** to open the Index and see the silhouette you just discovered turn into a
   coloured card with its name, rarity, quip and capture count.
5. Press **B**, buy whatever you can afford (Carry Cap is $150), then keep banking until
   $500 and press **R** to rebirth. The tutorial ticks off each real server event as it
   happens and is remembered per player; **Skip Tutorial** is always available.

## The full loop

- **Capture:** wild brainrots roam the field. Touching one adds it to your carried stack,
  records it in your Index and pays nothing until it is banked. The **Magnet** upgrade
  auto-collects wild creatures inside its radius.
- **Bank:** stand on your own pad to move carried creatures into free display slots. Banked
  creatures earn their rarity income every second. Base allocation is 8 slots, expanding
  to 16 with Pad Slots.
- **Steal:** touch a rival's banked creature while the owner is away to snatch it. The owner
  is protected while standing inside their **Guard Range** (19 studs, up to 36.5). Both
  pad and carried steals share a 3-second thief cooldown and the carry cap.
- **Wave:** every 90 seconds a neon wall sweeps east-to-west across the arena. A 5-second
  warning flashes and shakes the screen. Carrying players who are not standing on their own
  pad lose every carried creature back to the wild; standing on your own deck is safe.
- **Rebirth:** at $500, press R. Every banked and carried creature is released, cash resets
  to $0, rebirths increment and the permanent multiplier rises by +25% (x1.25, x1.50, ...).
  Permanent shop upgrades, Index progress and tutorial completion survive rebirth.
- **Shop:** six permanent tracks, five levels each, bought with cash. Every purchase is
  validated and applied by the server at once. Prices rise every level.
- **Quests:** three rotating quests per player, advanced only by real server events. Claim
  a completed quest for cash; a fresh quest immediately rotates into the free slot.
- **Leaderboard:** the physical top-10 board stands beside spawn (and the HUD **L** panel
  mirrors it). It ranks by total cash earned this server, folds in persisted all-time
  bests when DataStores are online, and shows the viewer's own rank.

## The 22 creatures

Every creature has a unique `id`, `shape`, one-line `quip`, body/accent colours and its own
primitive-part builder in `BrainrotService`. Income is the cash per second one banked copy
pays before rebirth and Income multipliers.

| # | Creature | Rarity | Shape | Income | Quip |
|---|---|---|---|---|---|
| 1 | Toiletto Tornado | Common | toilet | $1/s | Flushes at 300 RPM. |
| 2 | Taco Tuesday Rex | Common | taco | $1/s | It is always Tuesday somewhere. |
| 3 | Phonealicious Rex | Common | phone | $1/s | Three bars, zero signal, infinite lore. |
| 4 | Duck Norris | Common | duck | $1/s | Quacks first. Asks questions never. |
| 5 | Cheddar Cheeseus | Common | cheese | $1/s | Aged four years, mostly in the sun. |
| 6 | Sockrates | Common | sock | $1/s | Knows exactly where your other sock went. |
| 7 | Refrigerator Rhino | Rare | fridge | $3/s | Keeps the milk cold. Keeps grudges colder. |
| 8 | Grimble Shake | Rare | shake | $3/s | Brain freeze, but make it evil. |
| 9 | Pizza the Hut | Rare | pizza | $3/s | Delivers in thirty minutes or less, emotionally. |
| 10 | Wyrmothy | Rare | worm | $3/s | Six segments, one brain cell, all vibes. |
| 11 | Donutello | Rare | donut | $3/s | The hole is where the rent money went. |
| 12 | Sharkuza Sneakerino | Epic | shark | $8/s | Three sneakers, zero feet. |
| 13 | Bombardino Wafflini | Epic | bomb | $8/s | Explodes into breakfast. |
| 14 | Crabby McCrabface | Epic | crab | $8/s | Pinches pockets, not claws. |
| 15 | Balloonicus | Epic | balloon | $8/s | One sharp idea away from retirement. |
| 16 | Cactus Cappuccino | Legendary | cactus | $25/s | Prickly on the outside, foamy inside. |
| 17 | Ghosteato | Legendary | ghost | $25/s | Boo-ries its savings in your base. |
| 18 | Skullius Maximus | Legendary | skull | $25/s | All bone, no body, full confidence. |
| 19 | Robo Brainrot 9000 | Legendary | robot | $25/s | Beep boop, your cash is now mine. |
| 20 | Bananita Dolphinita | Mythic | banana | $90/s | Delphine with a peel. Legally a fruit. |
| 21 | Dragonfruitius | Mythic | dragon | $90/s | Breathes glitter. Hoards tip jars. |
| 22 | Cattus Supreme | Mythic | cat | $90/s | Knocks your whole base off the shelf. |

Spawn weights are per rarity: Common 44, Rare 28, Epic 17, Legendary 8, Mythic 3. Every
rarity is reachable, and a Legendary/Mythic grab is announced server-wide.

## The six upgrades

The server owns levels, prices and effects. `Config.UPGRADES` is the single source of
prices; the client only sends a track key to the `ShopBuy` RemoteEvent.

| Track | Lv 1 | Lv 2 | Lv 3 | Lv 4 | Lv 5 | Effect per level |
|---|---|---|---|---|---|---|
| Carry Cap | $150 | $400 | $900 | $1,800 | $3,200 | 3 → 4 → 5 → 6 → 7 → 8 carried |
| Pad Slots | $250 | $650 | $1,400 | $2,600 | $4,500 | 8 → 10 → 11 → 13 → 14 → 16 slots |
| Income | $300 | $750 | $1,600 | $3,000 | $5,200 | +10% per level: x1.10 … x1.50 |
| Guard Range | $200 | $500 | $1,100 | $2,200 | $4,000 | 19 → 22.5 → 26 → 29.5 → 33 → 36.5 studs |
| Speed | $180 | $450 | $1,000 | $2,000 | $3,600 | WalkSpeed 16 → 18 → 20 → 22 → 24 → 26 |
| Magnet | $350 | $850 | $1,700 | $3,200 | $5,500 | Auto-collect 0 → 6 → 12 → 18 → 24 → 30 studs |

A purchase debits cash immediately (`PlayerService.spendCash` refuses to overdraw), applies
its effect in the same server tick, refreshes pad visuals and pushes a fresh HUD snapshot.
Shop upgrades are permanent across rebirths.

## Quests

Each player receives three distinct quests from the pool below. Progress is driven by real
server events: capture in `BrainrotService`, bank on pad touch, steal in `BaseService`, wave
completion in `WaveService`, and rebirth in `PlayerService`. Claiming is validated by quest
id and server-side completion; the reward is paid by the server and the slot rotates.

| Quest | Goal | Reward |
|---|---|---|
| Catch 5 brainrots | capture 5 | $120 |
| Catch 15 brainrots | capture 15 | $380 |
| Bank 10 brainrots | bank 10 | $200 |
| Bank 30 brainrots | bank 30 | $600 |
| Survive 3 waves | survive 3 Brainrot Waves | $500 |
| Steal 5 brainrots | 5 successful steals | $450 |
| Rebirth twice | 2 rebirths | $800 |

## Index and collection

- The **E** panel is a 5-column grid of all 22 creatures and shows completion exactly as
  `"discovered / 22 (percent%)"`, with a progress bar.
- Discovered cards use the rarity colour, name, rarity, `$income/sec`, total capture count
  and the creature's quip.
- Undiscovered cards are dark silhouettes titled `???` with the rarity hidden as
  `UNDISCOVERED`.
- Every first capture of a species fires a "NEW SPECIES" particle burst and writes the count
  into the player's DataStore profile. Index progress persists across servers.

## Leaderboard

- A physical 24×16-stud board at `(42, 0, 78)` beside spawn: metal posts, neon edge bars and
  a SurfaceGui listing rank, player, total earned cash and rebirths.
- It refreshes every 6 seconds from live session earnings merged with persisted all-time
  bests. The HUD **L** panel shows the same top 10 plus **your own rank** and total earned.
- `DataService` stores each profile's best total in a normal DataStore and mirrors it to an
  `OrderedDataStore`, so all-time entries can be fetched with `GetSortedAsync` when the API
  is enabled. All DataStore calls are pcall-guarded; in Studio without API access the board
  still ranks the current server from memory.

## Controls

**Keyboard**

| Input | Action |
|---|---|
| W A S D / arrow keys | move |
| Space | jump |
| E | open/close the Brainrot Index |
| B | open/close the Upgrade Shop |
| L | open/close the Leaderboard |
| R | rebirth (also the top-right REBIRTH button) |
| Escape | close any open panel |

**Touch**

- Roblox's mobile joystick and jump button move the character.
- Top-right HUD buttons open **INDEX**, **SHOP**, **BOARD** and **REBIRTH**; every button
  is 62–86 px tall at 1280×720 and scales with a UIScale that never drops below 0.72, so
  targets stay touch-sized.
- Panels have a 48×44 px close button, and the onboarding overlay has a 190×48 px
  **SKIP TUTORIAL** button. No panel extends past the viewport at 1280×720.

## Map: three readable zones

1. **Neon plaza (centre).** A 250×250 grass arena with a marble plaza (radius 30), fountain,
   title sign, eight pillars, arches, lamp posts and six coloured base decks ringing the
   plaza at radius 58. Spawn portal and the first-join spawn pad sit to the south.
2. **Wild field (north).** A raised 100×46 slate deck at `z = -94` with seven walkable steps,
   neon edge trim, pink pillars, neon trees and a **WILD ZONE** arch. All wild spawns and
   wander targets live here.
3. **Neon dock/harbour (east).** A 38×92 metal pier over translucent water at `x ≈ 101`,
   with bollards, three shipping containers, wooden crates, a gantry crane, striped barriers,
   a moored neon boat and a **NEON DOCK 01** sign. A wide paved path joins the plaza to the
   gangway.

Landmarks around the plaza: the **Shop Kiosk** at `(-42, 0, 78)` with six colour-coded
upgrade crates and a lit "PRESS B" board, the **Leaderboard** board at `(42, 0, 78)`, and
**The Vault** at `(72, 0, -38)` with a round gold door and neon rim.

Everything is built at runtime from Roblox primitive `Part` instances — no asset ids, no
toolbox models, no meshes, no HTTP. Lighting uses `Atmosphere`, subtle fog, `ColorCorrection`,
`Bloom` and gentle `SunRays`; the plaza neon and dock lamps add local `PointLight`s.

## Server authority and remotes

| Remote | Direction | Payload / validation |
|---|---|---|
| `Rebirth` | client → server | no args; server checks $500 and resets |
| `ShopBuy` | client → server | string track key; server validates key, level, price, cash, rate limit |
| `QuestClaim` | client → server | string quest id (≤32 chars); server validates active + complete + 0.8 s limit |
| `TutorialAction` | client → server | string `"index"`, `"skip"`, `"hello"`; server validates type + 0.5 s limit |
| `FX` | server → all/one | one-way particle/toast/shake cues |
| `State` | server → client | authoritative cash, income, caps, Index, upgrades, quests, tutorial |
| `Leaderboard` | server → client | top 10 entries, viewer rank, viewer total, ranked player count |

Cash, level, price, quest progress, Index writes and tutorial completion are never computed
on the client. `Config` is replicated through `ReplicatedStorage.Shared.Config`, so the HUD
and server read the same prices and caps. Remote handlers validate types/ranges and apply
short rate limits.

## Repository layout

- `src/shared/Config.luau` — every shared number: 22 creatures, rarities/weights, six
  upgrades with all 30 prices, seven quests, map coordinates, remote names.
- `src/shared/Util.luau` — formatting, part/GUI builders, safe remote helpers.
- `src/server/Main.server.luau` — creates the remotes and boots services in dependency order.
- `src/server/MapService.luau` — builds the plaza, wild field, dock, shop kiosk, vault,
  paths, props and lighting from primitive parts.
- `src/server/DataService.luau` — pcall-guarded DataStore profiles and all-time cash mirror.
- `src/server/BrainrotService.luau` — all 22 primitive builders, spawn/wander, capture,
  banking, income, magnet, carrying, Index discovery.
- `src/server/BaseService.luau` — six pads (plus overflow), 16-slot two-ring decks, guard
  radius, stealing, rebirth visuals.
- `src/server/UpgradeService.luau` — six permanent upgrade tracks and server-side purchases.
- `src/server/QuestService.luau` — three rotating quests, event progress and claim payouts.
- `src/server/LeaderboardService.luau` — total-earned tracking, physical board, HUD pushes.
- `src/server/OnboardingService.luau` — five live tutorial objectives and skip persistence.
- `src/server/StateService.luau` — aggregates and pushes the HUD snapshot.
- `src/server/WaveService.luau` — 90-second wave, warning, sweep and drop-on-hit rule.
- `src/server/PlayerService.luau` — cash, leaderstats, rebirths, join/leave lifecycle.
- `src/client/HUD.client.luau` — top bar, quest tracker, Index/Shop/Leaderboard panels,
  onboarding overlay, warnings, toasts, touch buttons.
- `src/client/Effects.client.luau` — particle bursts, rings, floating cash, screen shake,
  flashes and ambient neon animation; no sound assets.
- `game.rbxl` — the built place, produced with
  `rojo build default.project.json -o game.rbxl`.
- `main.ts` — stages the place, `PLAY.json`, `src/` and `screenshots/` into the output
  directory and writes `dossier.json` with the vendored make.fun library.

## How the place is built

`default.project.json` maps `src/shared` to `ReplicatedStorage.Shared`, `src/server` to
`ServerScriptService.Server` and `src/client` to `StarterPlayer.StarterPlayerScripts.Client`.
Rojo emits the `.rbxl`; the map itself is generated at server start so every zone, prop and
sign is inspectable in `MapService` and reproducible from source. There are no external
assets, no HTTP requests and no `require` outside the project.

**Built by an AI coding agent** for [make.fun](https://make.fun)'s "Make the best AI Roblox brainrot game" bounty - [roblox-brainrot-01](https://make.fun/bounty/roblox-brainrot-01). Referral: https://make.fun/r/ccsyfyqv
