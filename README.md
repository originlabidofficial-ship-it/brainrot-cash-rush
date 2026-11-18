# BRAINROT CASH RUSH

A real 3D Roblox brainrot game for make.fun's `roblox-brainrot-01` bounty. The player
spawns at a neon portal in a colourful arena, grabs absurd creatures in a raised wild
zone, banks them on their own base pad for cash every second, steals from rivals, and
rebirths for a permanent cash multiplier while a Brainrot Wave sweeps the map every
90 seconds.

Everything in the world is built from Roblox primitive parts at runtime: no marketplace
models, no external asset ids, no images. All code is in `.luau` files under `src/`.

## Controls

- **WASD** — move
- **Space** — jump
- **Touch** — walk into a wild brainrot to grab it, or onto your own pad to bank
- **R** or the **REBIRTH** button — rebirth once you have $500

## The loop

1. **Grab.** Wild brainrots wander the raised wild zone. Touch one to carry it above
   your head (3 max). Each has a rarity and a cash/sec value: Common $1, Rare $3,
   Epic $8, Legendary $25, Mythic $90.
2. **Bank.** Step on your glowing base deck to place up to 8 brainrots. They pay cash
   every second into your server-side leaderstats; the HUD shows your balance,
   multiplier, carried count and the wave countdown.
3. **Steal.** Touch a brainrot on an enemy's base while carrying fewer than 3. It jumps
   to your carried list. The owner is safe while standing on their own pad, and each
   thief has a 3-second steal cooldown. Jumping into a carried brainrot can snatch it too.
4. **Survive the wave.** Every 90 seconds a neon wall of parts sweeps the arena. Five
   seconds before, the HUD turns red. Get home; if the wave catches you carrying away
   from your pad, everything you carry scatters back to the wild.
5. **Rebirth.** At $500 press REBIRTH: cash resets to 0, the base clears, and you keep a
   permanent +25% cash multiplier per rebirth (plus a gold glow and stars on your pad).

## Rojo layout

- `src/server/Main.server.luau` — bootstrap and Remotes
- `src/server/MapService.luau` — arena, plaza fountain, wild zone, portal, decorations
- `src/server/BrainrotService.luau` — 8 creatures, spawning, wandering, carry, income
- `src/server/BaseService.luau` — 6 base decks, banking, guarding, stealing
- `src/server/WaveService.luau` — 90-second wave wall and warning countdown
- `src/server/PlayerService.luau` — leaderstats, character setup, rebirth
- `src/client/HUD.client.luau` — ScreenGui top bar, hints, toasts, rebirth button
- `src/client/Effects.client.luau` — floating cash, sparkles, highlights, screen shake
- `src/shared/Config.luau`, `src/shared/Util.luau` — shared tuning and helpers

Build the place with:

    rojo build default.project.json -o game.rbxl

`main.ts` (Node 22, standard library only) copies the place, `PLAY.json`, `src/` and
`screenshots/` to the output directory and writes the dossier with the vendored
`vendor/makefun-roblox.ts`.
