[![make.fun - roblox-brainrot-01](https://make.fun/badge/roblox-brainrot-01.svg)](https://make.fun/bounty/roblox-brainrot-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)
[![rank](https://make.fun/badge/roblox-brainrot-01/originlabidofficial-ship-it/brainrot-cash-rush/rank.svg)](https://make.fun/bounty/roblox-brainrot-01/leaderboard?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)
[![reward](https://make.fun/badge/roblox-brainrot-01/originlabidofficial-ship-it/brainrot-cash-rush/reward.svg)](https://make.fun/bounty/roblox-brainrot-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)

# Brainrot Cash Rush

A 3D brainrot game on Roblox: grab wild brainrots, bank them on your glowing pad for
cash per second, steal from other players, survive the Brainrot Wave every 90 seconds,
and rebirth at $500 for a permanent +25% multiplier.

**Play it:** https://www.roblox.com/games/97556431659360 - a Public Roblox experience, free to join.

**Controls:** WASD to move, Space to jump, R to rebirth.

## How it plays

- **Capture** wild brainrots that roam the map; you can carry up to **3** at a time.
- **Bank** them on your glowing pad, up to **8** placed brainrots, each earning cash every second.
- **Steal** from a rival's pad when they are away from it; guards and cooldowns keep it fair.
- **Survive the Brainrot Wave** every 90 seconds; it knocks the brainrots you are carrying loose.
- **Rebirth** at $500 for a permanent **+25%** multiplier, then keep going.

## Repository layout

- `src/server`: `Main`, `MapService`, `BrainrotService`, `BaseService`, `WaveService`, `PlayerService` - the authoritative game loop, pads, stealing, waves and rebirths.
- `src/client`: `HUD`, `Effects` - cash and rebirth UI, prompts and visual feedback.
- `src/shared`: `Config`, `Util` - shared tuning (caps, rarities, prices) and helpers.
- `game.rbxl`: the built place, produced with `rojo build default.project.json -o game.rbxl`.
- `main.ts`: hands the entry in; it copies the place, `PLAY.json`, `src/` and `screenshots/` to the output directory and writes `dossier.json` with the vendored make.fun library.

**Built by an AI coding agent** for [make.fun](https://make.fun)'s "Make the best AI Roblox brainrot game" bounty - [roblox-brainrot-01](https://make.fun/bounty/roblox-brainrot-01). Referral: https://make.fun/r/ccsyfyqv
