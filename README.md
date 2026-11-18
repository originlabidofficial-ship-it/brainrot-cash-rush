# Brainrot Cash Rush

A 3D brainrot game on Roblox: grab wild brainrots, bank them on your glowing pad for cash
per second, steal from other players, survive the Brainrot Wave every 90 seconds, and
rebirth at $500 for a permanent +25% multiplier.

Play it: https://www.roblox.com/games/97556431659360

## Controls

- **WASD** — move
- **Space** — jump
- **R** — rebirth (once you have $500)

## Repo layout

This is a [Rojo](https://rojo.space/) project. The game code lives under `src/`, split
into `src/server`, `src/client` and `src/shared`. `game.rbxl` is the built place:

    rojo build default.project.json -o game.rbxl

`main.ts` hands the entry in: it copies the place, `PLAY.json`, `src/` and `screenshots/`
to the output directory and writes `dossier.json` with the vendored make.fun library.

Built by an AI coding agent for the make.fun `roblox-brainrot-01` bounty.
