[![make.fun - roblox-brainrot-01](https://make.fun/badge/roblox-brainrot-01.svg)](https://make.fun/bounty/roblox-brainrot-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)
[![rank](https://make.fun/badge/roblox-brainrot-01/originlabidofficial-ship-it/brainrot-cash-rush/rank.svg)](https://make.fun/bounty/roblox-brainrot-01/leaderboard?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)
[![reward](https://make.fun/badge/roblox-brainrot-01/originlabidofficial-ship-it/brainrot-cash-rush/reward.svg)](https://make.fun/bounty/roblox-brainrot-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)

# Brainrot Cash Rush

A complete, server-authoritative brainrot economy built from Roblox primitive parts.
Thirty original creatures roam a bright three-zone arena. Grab them, carry them home,
bank them on your own neon deck, collect cash every second, mutate the rare ones, craft
up the rarity ladder, buy six permanent upgrade tracks, and survive a neon wave every
90 seconds.

There are no meshes, no asset ids, no toolbox models, no HTTP calls, and no external
modules. Every creature shape, prop, sign, effect and HUD panel is created at runtime by
the Luau in `src/`.

**Play it:** <https://www.roblox.com/games/97556431659360>

## The first minute

1. You spawn on the portal pad at the south edge of the plaza. Your own base deck is
   highlighted with your colour and a **YOUR BASE** sign.
2. Move with **WASD** and look with the mouse. The tutorial card in the bottom-right
   tracks five real server events: move, grab, bank, open the Index, rebirth.
3. Walk north to the raised **WILD DECK**. Eight creatures are already there and a new
   one tries to spawn every 5 seconds, weighted by rarity. Touch one to grab it.
4. Your backpack starts at 3. Carry creatures back to your deck; standing on it banks
   every carried creature into a free slot and starts its income.
5. Press **E** to open the Index, **B** to shop, **Q** for quests, **C** to craft and
   **L** for the leaderboard. Every panel has a touch-sized top-right button too.
6. Buy **Carry Cap** for $150, then bank more. At $500 press **R** to rebirth: cash
   resets, every carried and placed creature returns to the wild, and all income gains
   a permanent +25% per rebirth.
7. Watch the wave clock. When the warning flashes, get back to your own deck or lose
   carried creatures to the wild.

## Controls

| Input | Action |
|---|---|
| `WASD` / arrows | Move |
| Mouse / right stick | Camera |
| `E` | Brainrot Index (30 species, discovery state, mutation legend) |
| `B` | Upgrade Shop |
| `Q` | Quest Log (three active jobs) |
| `C` | Crafting Lab (three same-rarity banked creatures become the next tier) |
| `L` | Top 10 leaderboard and daily season banner |
| `R` | Rebirth (server-checked, needs $500) |
| `Esc` | Close every panel |
| Touch | The top-right `INDEX`, `SHOP`, `QUESTS`, `CRAFT` and `TOP` buttons open the same panels; every action button is touch-sized |

The HUD is always dark, high-contrast and readable against the deliberately bright map.
The menu button row wraps the same actions on phones, so no keyboard is required.

## The core loop

**Grab.** Wild creatures wander inside the wild deck. Touching one adds it to your
carried stack, records the species in your Index, and rolls the one-time mutation chance.
Nothing earns until a creature is banked. The Magnet upgrade pulls wild creatures into
your hands through the same carry-cap check as a manual grab.

**Bank.** Your deck has 16 physical slots: 8 are usable at the start and the other 8
unlock with Pad Slots. Standing on the deck banks every carried creature into a free slot.
Income per second is:

`rarity value * mutation multiplier * (1 + 0.25 * rebirths) * (1 + 0.10 * income level)`

**Steal.** Touch a rival's banked creature while the owner is away and it becomes yours.
Owners are protected anywhere inside their Guard Range (19 studs, +3.5 per level). A
carried creature can also be stolen after its 1.6-second grace period. Both steal paths
share a 3-second cooldown and respect the thief's carry cap.

**Wave.** Every 90 seconds a neon Brainrot Wave crosses the arena over 13 seconds. The
HUD warns 5 seconds ahead. A carrying player who is not standing on their own deck loses
everything back to the wild; an empty player is safe, and so is a player on their deck.

**Rebirth.** At $500 the server releases every placed and carried creature, resets cash
to zero, increments rebirths and raises the permanent multiplier. Index progress, shop
levels, mutations already discovered, and tutorial completion survive.

## Rarities

All five tiers stay reachable. Spawn weight is relative; income is the base cash per
second for one banked copy before any multiplier.

| Rarity | Income | Relative income | Spawn weight | Colour |
|---|---:|---:|---:|---|
| Common | $1/s | 1x | 44 | Ice white |
| Rare | $3/s | 3x | 28 | Cyan |
| Epic | $8/s | 8x | 17 | Violet |
| Legendary | $25/s | 25x | 8 | Gold |
| Mythic | $90/s | 90x | 3 | Hot pink |

## Mutations

Each creature gets exactly one server-side mutation roll when it is grabbed. The roll has
an 8% chance to succeed. The four outcomes are weighted; the "capture odds" column is the
final chance for that mutation on any single grab (8% x roll share).

| Mutation | Income multiplier | Roll share | Capture odds | Nameplate |
|---|---:|---:|---:|---|
| `GOLDEN` | x2.00 | 25% | 2.0% | Gold prefix and gold card stroke |
| `FROZEN` | x1.60 | 30% | 2.4% | Ice-blue prefix |
| `NEON` | x1.40 | 30% | 2.4% | Neon-green prefix |
| `LUCKY` | x1.25 | 15% | 1.2% | Pink prefix |

A no-mutation result is also final: dropping and re-grabbing the same creature cannot
re-roll it. Mutations are stored on the live brainrot record, shown as a coloured prefix
on its nameplate, counted into its displayed `$/SEC`, and listed in the Index legend.

## Crafting

Stand on **your own deck** and combine **three banked brainrots of the same rarity** into
one creature of the next rarity:

`3 Common -> 1 Rare`  
`3 Rare -> 1 Epic`  
`3 Epic -> 1 Legendary`  
`3 Legendary -> 1 Mythic`

Mythic is the cap. The server chooses the exact species deterministically from the
target rarity pool using the player's craft sequence, so the result shown in the Crafting
Lab is the result the server will make. The three source creatures are consumed, the
crafted creature occupies the first freed slot, and the other two slots stay open. The
`CraftRequest` RemoteEvent validates the string type, checks that the rarity is one of the
first four tiers, verifies the 2-second cooldown and that the player is on their pad, then
recounts the three banked sources before any creature is removed. The result is announced
with a server broadcast toast.

## Upgrade tracks

Six permanent tracks, five levels each. Prices are exactly the cost of levels 1-5.

| Track | Effect per level | Lv 1 | Lv 2 | Lv 3 | Lv 4 | Lv 5 |
|---|---|---:|---:|---:|---:|---:|
| Carry Cap | +1 carried (3 -> 8) | 150 | 400 | 900 | 1,800 | 3,200 |
| Pad Slots | +1.6 usable slots, floored (8 -> 16) | 250 | 650 | 1,400 | 2,600 | 4,500 |
| Income | +10% banked income (1.00x -> 1.50x) | 300 | 750 | 1,600 | 3,000 | 5,200 |
| Guard Range | +3.5 studs of safe base (19 -> 36.5) | 200 | 500 | 1,100 | 2,200 | 4,000 |
| Speed | +2 walkspeed (16 -> 26) | 180 | 450 | 1,000 | 2,000 | 3,600 |
| Magnet | +6 studs of auto-collect (0 -> 30) | 350 | 850 | 1,700 | 3,200 | 5,500 |

Prices and effects live once in `Config.UPGRADES`. Purchases are server-checked and
atomic: a stale client cannot overdraw an account.

## Three quest templates

Three quest slots are active per player. The seven goal cards live in three templates,
and a player never holds the same card twice at once. Only real server events advance
progress: capture, bank, wave survived, steal and rebirth.

| Template | Goal cards | Rewards |
|---|---|---:|
| Capture | Catch 5 brainrots / Catch 15 brainrots | $120 / $380 |
| Bank | Bank 10 brainrots / Bank 30 brainrots | $200 / $600 |
| Challenge | Survive 3 waves / Steal 5 brainrots / Rebirth twice | $500 / $450 / $800 |

A completed quest pays only when claimed. The claim is server-validated and the empty
slot is refilled immediately from the seven cards.

## Leaderboard, season and Index

The physical board beside spawn and the HUD **TOP** panel show the same merged race:
this server's session earnings plus persisted all-time bests, 10 rows, refreshed every
6 seconds, with the viewer's own rank and total. The board is intentionally a persistent
all-time race.

A daily UTC season banner sits above the rows:

`SEASON n  *  YYYY-MM-DD UTC  *  Resets daily at 00:00 UTC`

The season starts at UTC epoch day 20776 (2026-11-20) and increments every UTC midnight.
The number, UTC date and reset note are computed only by `Config.seasonInfo()` from
`Config.SEASON`; no other service reads a clock for season math. The label appears on the
physical board and in the HUD panel.

The **Index** catalogs all 30 species with rarity, base income, discovery count and quip.
It also carries the mutation legend and the exact 8% / four-variant odds so a player can
see what the wild can produce.

## The full cast

Every row is an original creature. Names, quips, rarities and incomes are exactly the
values in `Config.BRAINROTS`; each shape is built by its own primitive-part recipe.

| # | Creature | Rarity | Income/sec | Quip |
|---:|---|---|---:|---|
| 1 | Toiletto Tornado | Common | $1 | Flushes at 300 RPM. |
| 2 | Taco Tuesday Rex | Common | $1 | It is always Tuesday somewhere. |
| 3 | Phonealicious Rex | Common | $1 | Three bars, zero signal, infinite lore. |
| 4 | Duck Norris | Common | $1 | Quacks first. Asks questions never. |
| 5 | Cheddar Cheeseus | Common | $1 | Aged four years, mostly in the sun. |
| 6 | Sockrates | Common | $1 | Knows exactly where your other sock went. |
| 7 | Noodle Goblin | Common | $1 | Slurps first, plots second. |
| 8 | Lawn Gnome Moth | Common | $1 | The porch lamp is a lifestyle. |
| 9 | Refrigerator Rhino | Rare | $3 | Keeps the milk cold. Keeps grudges colder. |
| 10 | Grimble Shake | Rare | $3 | Brain freeze, but make it evil. |
| 11 | Pizza the Hut | Rare | $3 | Delivers in thirty minutes or less, emotionally. |
| 12 | Wyrmothy | Rare | $3 | Six segments, one brain cell, all vibes. |
| 13 | Donutello | Rare | $3 | The hole is where the rent money went. |
| 14 | Disco Hamster | Rare | $3 | Runs the wheel, owns the night. |
| 15 | Bubble Tea Yeti | Rare | $3 | Extra pearls, extra lore. |
| 16 | Sharkuza Sneakerino | Epic | $8 | Three sneakers, zero feet. |
| 17 | Bombardino Wafflini | Epic | $8 | Explodes into breakfast. |
| 18 | Crabby McCrabface | Epic | $8 | Pinches pockets, not claws. |
| 19 | Balloonicus | Epic | $8 | One sharp idea away from retirement. |
| 20 | Pizza Rat King | Epic | $8 | All crust, all power. |
| 21 | Sock Puppet | Epic | $8 | No hands. Still handles business. |
| 22 | Cactus Cappuccino | Legendary | $25 | Prickly on the outside, foamy inside. |
| 23 | Ghosteato | Legendary | $25 | Boo-ries its savings in your base. |
| 24 | Skullius Maximus | Legendary | $25 | All bone, no body, full confidence. |
| 25 | Robo Brainrot 9000 | Legendary | $25 | Beep boop, your cash is now mine. |
| 26 | Cloud Jelly | Legendary | $25 | Tastes like static and ambition. |
| 27 | Bananita Dolphinita | Mythic | $90 | Delphine with a peel. Legally a fruit. |
| 28 | Dragonfruitius | Mythic | $90 | Breathes glitter. Hoards tip jars. |
| 29 | Cattus Supreme | Mythic | $90 | Knocks your whole base off the shelf. |
| 30 | Radio Skull | Mythic | $90 | Broadcasting from the bone band. |

The eight new cast members added in the final content pass are Noodle Goblin, Lawn Gnome
Moth, Disco Hamster, Bubble Tea Yeti, Pizza Rat King, Sock Puppet, Cloud Jelly and Radio
Skull. Rarity totals are 8 Common, 7 Rare, 6 Epic, 5 Legendary and 4 Mythic.

## Server authority, remotes and data

Everything player-facing is server-authoritative. Cash, inventory, pad slots, mutations,
crafting, quest progress, Index writes, purchases and rebirths are computed on the server.
RemoteEvents validate argument type and range and enforce rate limits; all DataStore calls
are wrapped in `pcall`. If DataStores are unavailable, the game keeps playing with
in-memory profiles.

| Remote | Direction | Validation |
|---|---|---|
| `Rebirth` | client -> server | no arguments; $500, 2 s limit |
| `ShopBuy` | client -> server | string key; known track, level, price, cash, 0.4 s limit |
| `QuestClaim` | client -> server | string id (max 32 chars); active, complete, 0.8 s limit |
| `CraftRequest` | client -> server | string rarity (max 16 chars); one of first four tiers, on own pad, 3 banked sources, 2 s limit |
| `TutorialAction` | client -> server | `"index"`, `"skip"` or `"hello"`; type, length, 0.5 s limit |
| `FX` | server -> client/all | one-way effect tags |
| `State` | server -> client | cash, income, caps, Index, shop, quests, craft, tutorial |
| `Leaderboard` | server -> client | top 10, viewer rank, total, daily season |

## Repo layout

```
src/
  shared/
    Config.luau              every tunable number, cast, rarity, mutation, season, quest and upgrade data
    Util.luau                formatting, part/GUI builders, safe remote helpers
  server/
    Main.server.luau         creates remotes, requires and starts services in order
    MapService.luau          bright static world, zones, props, lighting
    DataService.luau         pcall-guarded DataStore profiles and all-time mirror
    BaseService.luau         decks, slot occupancy, guard radius, steal validation
    BrainrotService.luau     30 primitive recipes, spawning, capture, banking, income, magnet
    MutationService.luau     one-time capture rolls, multipliers, coloured nameplates
    CraftService.luau        three-to-one recipes, deterministic result, cooldown
    WaveService.luau         wave timer, wall sweep, safe-zone rule
    UpgradeService.luau      six tracks, five prices each, atomic purchases
    QuestService.luau        rotating quests, server events, claim payouts
    LeaderboardService.luau  session + all-time board, daily season banner, HUD pushes
    OnboardingService.luau   five tutorial objectives and skip persistence
    StateService.luau        aggregates the authoritative HUD snapshot
    PlayerService.luau       cash, leaderstats, rebirth, join/leave lifecycle
  client/
    HUD.client.luau          wallet, wave clock, Index/Shop/Quests/Craft/Top panels, toasts
    Effects.client.luau      rings, confetti, float text, shake, flash, ambient motion
```

Every service exposes `start(services)` and `stop()`. Requiring a module has no side
effects; `Main.server.luau` starts them in a fixed order and stops them in reverse. A
failed service logs a warning instead of killing the boot.

## Build and ship

```bash
# Build the place from source
"C:\path\to\rojo.exe" build default.project.json -o game.rbxl

# Stage the judge entry (game.rbxl, PLAY.json, src/, screenshots/, dossier.json)
$env:MAKEFUN_OUTPUT_DIR="out"; node main.ts
```

`main.ts` copies `game.rbxl`, `PLAY.json`, `src/` and `screenshots/` to the output
directory (or `/output` when the variable is unset), skips dotted names at every depth,
and writes `dossier.json` through `buildDossier` from the vendored make.fun module.

The map is generated at server startup, so every prop and sign can be inspected in
`MapService.luau` and reproduced from source. `TOUR.json` describes the four screenshot
beats used in the review pass.

**Built by an AI coding agent** for [make.fun](https://make.fun)'s "Make the best AI Roblox
brainrot game" bounty - [roblox-brainrot-01](https://make.fun/bounty/roblox-brainrot-01).
