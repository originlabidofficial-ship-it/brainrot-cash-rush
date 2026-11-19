[![make.fun - roblox-brainrot-01](https://make.fun/badge/roblox-brainrot-01.svg)](https://make.fun/bounty/roblox-brainrot-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)
[![rank](https://make.fun/badge/roblox-brainrot-01/originlabidofficial-ship-it/brainrot-cash-rush/rank.svg)](https://make.fun/bounty/roblox-brainrot-01/leaderboard?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)
[![reward](https://make.fun/badge/roblox-brainrot-01/originlabidofficial-ship-it/brainrot-cash-rush/reward.svg)](https://make.fun/bounty/roblox-brainrot-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)

# Brainrot Cash Rush

A complete, playable brainrot economy for Roblox. Twenty-two original creatures roam a
bright three-zone arena; you grab them, carry them home, bank them on your own neon deck
and get paid every second. Cash buys six permanent upgrade tracks, completed quests pay
bonus cash, and a wave of neon sweeps the map every 90 seconds to punish greedy bankers.

Everything is built from Roblox primitive parts at runtime. There are no meshes, no asset
ids, no HTTP calls and no toolbox models: the whole game is the Luau in `src/`.

**Play it:** <https://www.roblox.com/games/97556431659360>

## Quick start

```bash
# Build the place file from source
rojo build default.project.json -o game.rbxl

# Stage the entry for the judge (place, PLAY.json, src/, screenshots/, dossier.json)
node main.ts
```

`main.ts` writes to `$MAKEFUN_OUTPUT_DIR` when set and to `/output` otherwise. It skips
dot-prefixed names at every depth and calls `buildDossier` from `vendor/makefun-roblox.ts`
with the same limits the scorer uses.

## The first minute

1. You spawn on the cyan portal pad at the south edge of the plaza.
2. The tutorial card in the bottom-right tracks five real server events: move, grab,
   bank, open the Index, rebirth. **SKIP TUTORIAL** is always available.
3. Walk north onto the wild deck. Eight creatures are already there; a new one tries to
   spawn every 5 seconds, weighted by rarity. Touch one to grab it. Base carry cap is 3.
4. Run back to your glowing deck. Standing on it banks every carried creature into a free
   slot. Each banked creature pays its rarity income every second.
5. Press **B** and buy Carry Cap for $150, keep banking, then press **R** at $500 to
   rebirth. Rebirth resets cash but permanently multiplies all income by +25%.

## Controls

| Key | Action |
|---|---|
| `E` | Brainrot Index (all 22 species, discovery state, quip) |
| `B` | Upgrade Shop |
| `Q` | Quest Log |
| `L` | Top 10 leaderboard |
| `R` | Rebirth (asks the server; needs $500) |
| `Esc` | Close every panel |

The same actions exist as touch-sized buttons in the top-right menu, so the game is fully
playable on a phone without a keyboard.

## The loop

**Grab.** Wild creatures wander inside the raised wild deck. Touching one adds it to your
carried stack and records it in the Index. Nothing is paid until it is banked. The Magnet
upgrade pulls wild creatures inside its radius into your hands, through the same carry-cap
check as a manual grab.

**Bank.** Your deck has sixteen physical slots: eight are usable at the start, the remaining
eight unlock with Pad Slots. Standing on the deck banks every carried creature into a free
slot. Income is `rarity value × (1 + 0.25 × rebirths) × (1 + 0.10 × income level)`.

**Steal.** Touch a rival's banked creature while the owner is away and it becomes yours.
Owners are protected while standing inside their Guard Range (19 studs, +3.5 per level).
Stealing a creature that is being carried is also possible after a 1.6-second grace period.
Both steals share a 3-second cooldown and respect the thief's carry cap.

**Wave.** Every 90 seconds the Brainrot Wave crosses the arena east to west over 13 seconds.
The HUD flashes and warns 5 seconds ahead. A carrying player who is not standing on their own
deck loses everything back to the wild; standing on your deck is safe, and so is being empty.

**Rebirth.** At $500 the server releases every placed and carried creature, resets cash to
zero, increments rebirths and raises the permanent multiplier. Index progress, shop levels
and tutorial completion all survive.

**Quests.** Three quests are active per player at a time, drawn from seven definitions. Only
server events advance them: capture, bank, wave survived, steal, rebirth. A completed quest
pays its reward when claimed and is replaced immediately.

**Leaderboard.** The physical board beside spawn and the HUD panel show the same merged
table: this session's earnings plus persisted all-time bests, with the viewer's own rank.

## The cast

Each creature has an `id`, a `name`, a `rarity`, a `shape` recipe, body and accent colours,
and a one-line `quip`. Income is the cash per second one banked copy pays before multipliers.

| # | Creature | Rarity | Shape | Income |
|---|---|---|---|---|
| 1 | Toiletto Tornado | Common | toilet | $1/s |
| 2 | Taco Tuesday Rex | Common | taco | $1/s |
| 3 | Phonealicious Rex | Common | phone | $1/s |
| 4 | Duck Norris | Common | duck | $1/s |
| 5 | Cheddar Cheeseus | Common | cheese | $1/s |
| 6 | Sockrates | Common | sock | $1/s |
| 7 | Refrigerator Rhino | Rare | fridge | $3/s |
| 8 | Grimble Shake | Rare | shake | $3/s |
| 9 | Pizza the Hut | Rare | pizza | $3/s |
| 10 | Wyrmothy | Rare | worm | $3/s |
| 11 | Donutello | Rare | donut | $3/s |
| 12 | Sharkuza Sneakerino | Epic | shark | $8/s |
| 13 | Bombardino Wafflini | Epic | bomb | $8/s |
| 14 | Crabby McCrabface | Epic | crab | $8/s |
| 15 | Balloonicus | Epic | balloon | $8/s |
| 16 | Cactus Cappuccino | Legendary | cactus | $25/s |
| 17 | Ghosteato | Legendary | ghost | $25/s |
| 18 | Skullius Maximus | Legendary | skull | $25/s |
| 19 | Robo Brainrot 9000 | Legendary | robot | $25/s |
| 20 | Bananita Dolphinita | Mythic | banana | $90/s |
| 21 | Dragonfruitius | Mythic | dragon | $90/s |
| 22 | Cattus Supreme | Mythic | cat | $90/s |

Rarity spawn weights are 44 / 28 / 17 / 8 / 3 for Common through Mythic.

## Upgrade tracks

| Track | Effect per level | Prices (Lv 1–5) |
|---|---|---|
| Carry Cap | +1 carried | 150 / 400 / 900 / 1800 / 3200 |
| Pad Slots | +1.6 pad slot (floored) | 250 / 650 / 1400 / 2600 / 4500 |
| Income | +10% banked income | 300 / 750 / 1600 / 3000 / 5200 |
| Guard Range | +3.5 studs of safe base | 200 / 500 / 1100 / 2200 / 4000 |
| Speed | +2 walkspeed | 180 / 450 / 1000 / 2000 / 3600 |
| Magnet | +6 studs of auto-collect | 350 / 850 / 1700 / 3200 / 5500 |

## Map

1. **Plaza.** A 250×250 grass arena with a marble hub (radius 30), fountain, title board,
   eight neon-lit pillars, two arches and lamp posts. Six coloured base decks ring the hub
   at radius 58, with overflow decks built for late joiners.
2. **Wild deck.** A raised sand platform at `z = -94` with soft hills, a pink trim and a
   readable "WILD DECK" board. All wild spawns and wander targets live here.
3. **Harbour.** A wooden pier over translucent water at `x ≈ 101`, with bollards, a moored
   neon boat and a stone path from the plaza.

Landmarks: the Upgrade Shop kiosk at `(-42, 0, 78)`, the leaderboard board at
`(42, 0, 78)` and the Vault at `(72, 0, -38)`.

The lighting is deliberately bright (14:20 clock, high ambient, light fog, a little bloom)
and neon is used only for trim, signs and effects, so the HUD and the creatures stay
readable against the world.

## Architecture

```
src/
  shared/
    Config.luau        every tunable number, the cast table, upgrade and quest data
    Util.luau          formatting, part/GUI builders, safe remote helpers
  server/
    Main.server.luau   creates remotes, requires and starts services in order
    MapService.luau    static world: zones, props, lighting
    DataService.luau   pcall-guarded DataStore profiles + all-time mirror
    BaseService.luau   decks, slot occupancy, guard radius, steal validation
    BrainrotService.luau  shape recipes, spawning, carrying, banking, income, magnet
    WaveService.luau   wave timer, wall sweep, safe-zone rule
    UpgradeService.luau   six tracks, prices, atomic purchases
    QuestService.luau  rotating quests, event progress, claim payouts
    LeaderboardService.luau  earning totals, physical board, HUD pushes
    OnboardingService.luau  five tutorial objectives + skip persistence
    StateService.luau  aggregates the authoritative HUD snapshot
    PlayerService.luau cash, leaderstats, rebirth, join/leave lifecycle
  client/
    HUD.client.luau    wallet, wave clock, Index/Shop/Quests/Top panels, toasts
    Effects.client.luau  rings, confetti, float text, shake, flash, ambient motion
```

Every service exposes `start(services)` and `stop()`. Requiring a module has no side
effects; `Main.server.luau` starts them in a fixed order (map, data, bases, creatures,
waves, upgrades, quests, leaderboard, onboarding, state, players) and stops them in reverse
when the server closes. A failed service logs a warning instead of killing the boot.

Every player-facing number lives in `Config.luau` once: carry caps, spawn cadence, wave
timing, steal cooldown, prices, rewards, map coordinates and remote names. Services read
those values instead of hard-coding them, and the client reads the same replicated Config.

## Remotes and validation

| Remote | Direction | Payload and checks |
|---|---|---|
| `Rebirth` | client → server | no arguments; server checks $500, 2 s rate limit |
| `ShopBuy` | client → server | string key; server checks track, level, price, cash, 0.4 s limit |
| `QuestClaim` | client → server | string id (≤32 chars); server checks active, complete, 0.8 s limit |
| `TutorialAction` | client → server | `"index"`, `"skip"` or `"hello"`; type, length, 0.5 s limit |
| `FX` | server → client/all | one-way effect tags |
| `State` | server → client | cash, income, caps, Index, shop, quests, tutorial |
| `Leaderboard` | server → client | top 10, viewer rank, viewer total, player count |

Cash, levels, prices, quest progress, Index writes and tutorial completion are only ever
computed on the server. The client asks; the server validates and answers.

## Failure behaviour

- Every DataStore call is `pcall`-guarded. Without API access the game runs with in-memory
  profiles instead of failing to boot.
- A player who leaves mid-action is handled by nil/`Parent` checks in every service; creatures
  return to the wild instead of being orphaned.
- A wave always destroys its wall and re-arms the timer, even if a decorative part errors.
- The creature animation loop isolates each record with `pcall`, so one malformed model
  cannot freeze the other creatures or the banked displays.
- The banker/steal paths re-read the carry cap and slot list from the server on every action,
  so a stale client can never over-bank or over-steal.

## Building and shipping

`default.project.json` maps `src/shared` to `ReplicatedStorage.Shared`, `src/server` to
`ServerScriptService.Server` and `src/client` to `StarterPlayer.StarterPlayerScripts.Client`.
Rojo produces `game.rbxl`; the map is generated when the server starts, so every prop and
sign can be inspected in `MapService.luau` and reproduced from source.

`TOUR.json` describes the four screenshots a review pass should capture, including a
scripted wave summon through `WaveService.summon`.

**Built by an AI coding agent** for [make.fun](https://make.fun)'s "Make the best AI Roblox
brainrot game" bounty — [roblox-brainrot-01](https://make.fun/bounty/roblox-brainrot-01).
