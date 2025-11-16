# Mounted Warfare

A fast, stylish vehicular-combat homage to Vigilante 8: 2nd Offense — but instead of cars, you pilot extravagant mounts (mastodonts, larvae, stilt‑ticks, wind machines, oared galleys, and other Atlantean/biopunk contraptions) crewed by odd humanoid cultures. Think: Monster Hunter meets Vigilante 8 set in a colorful Avatar x Star Wars frontier.


## The Twist
- No cars. “Vehicles” are creatures and primitive/fantastical machines.
- Piloting is shared: the mount and one/many riders (health split, roles).
- Weapons range from blades/bows to animistic magic and bio‑devices (exploding fauna, flame‑throwing fauna, light‑emitting impacts, etc.).

## Core Gameplay Loop (MVP)
1. Enter an arena as a chosen mount+crew.
2. Collect pickups (weapons, ammo, repair, boosts).
3. Fight AI rivals; use positioning, unique movement, and hardpoints.
4. Earn salvage on kills/assists; between rounds, upgrade offense/defense/speed/targeting.
5. Visuals reflect upgrades (attachments, plating, totems, pods).

## Early Scope (MVP)
- Camera: third‑person chase 
- Single‑player vs bots
- 1 test arena (obstacles, hazards, pickup spawners)
- 1 flagship mount (Mastodont) + basic movement model
- 2–3 weapons (rockets, mines, optional autocannon)
- Simple AI drivers (patrol → engage → evade)
- Salvage upgrades (tiered: offense/defense/speed/targeting)

## Systems Overview
- Movement: weighty, readable; mount‑specific quirks later (brachiating, skimming, stomping).
- Weapons: lock‑ons, splash, proximity traps; each with unique ammo and fire modes.
- Pickups: weapon crates, ammo, repair, armor, speed/boost.
- Salvage: earn in matches; spend to improve stats and attach visible parts.
- Health Model: split HP for mount and rider(s); armor mitigation and hit zones.

## Aesthetic Direction
- “Atlantean Star Wars”: saturated colors, bold silhouettes, readable VFX.
- Biopunk tech: creatures as mechanisms; ritual trappings; totems and textiles.
- Environments: evocative, odd geography; practical hazards; minimal text/lore.

## Roadmap (Short-Term)
- Prototype driving and combat feel (1 mount, 2 weapons, 1 arena).
- Add pickups and salvage loop; confirm visual upgrade feedback.
- Bot behaviors and lock‑on/special weapon pass.
- Juice pass: SFX, VFX, hit feedback, concise combat logs.

## Longer-Term Ideas
- 10+ species (cultures/tech trees → unique mounts and weapons).
- Mobility mods (skis, hover pods, grapnels) per environment.
- Co‑op hunts and multi‑crew mounts with role actions.

## Design Pillars
- Distinct silhouettes (every mount is instantly recognizable).
- Tactile readability (movement and impact always clear).
- Expressive builds (mechanically and visually meaningful upgrades).

---

## Development Principles (Read Me First)

We design for scalability, modularity, and loose coupling. Follow these core guidelines:

- Signals over direct references: Use node signals and the global `EventBus` to communicate between systems without tight coupling.
- Centralized services: Access shared systems via the `Services` autoload (logger, event bus, config) instead of hardcoded `/root/...` paths.
- Strict typing: All variables and function parameters should have explicit types. Avoid Variant inference with `:=` unless you annotate.
- Composition over inheritance: Prefer small, focused nodes and scripts with clear responsibilities.
- Clear naming and structure: Node names in PascalCase, functions/variables in snake_case; keep methods under ~30 lines when possible.
- Editor connections for static relationships; code connections for dynamic ones. Disconnect signals when nodes are freed.
- Robust logging: Use `LoggerInstance` with categories and levels. Emit meaningful, throttled logs with context and emojis for stat deltas.
- Performance-minded: Lean scene trees, physics layers, object pooling for frequent spawns, packed arrays for heavy data.

A detailed, canonical set of rules lives in `godotconventions.mdc`. If you’re unsure, defer to those rules.

### Core Architecture

- `scripts/core/services.gd` (autoload: `Services`)
  - Single access point for shared systems: `logger()`, `bus()`, `config()`.
- `scripts/core/event_bus.gd` (autoload: `EventBus`)
  - Global, typed signals for decoupled messaging (e.g., `ammo_changed`, `weapon_fired`, `player_health_changed`, `target_changed`, `movement_intent`, `ai_decision`).
- `scripts/core/config.gd` (autoload: `GameConfig`)
  - Defaults and designer toggles; central place for groups, feature flags, and category visibility.
- `scripts/core/logger.gd` (autoload: `LoggerInstance`)
  - Category/level gating, throttling, file logging to `res://log.txt`, guard helpers, and dev assertions.

### Autoload Setup (Project → Project Settings → Autoload)

Add these singletons:
- Path `scripts/core/logger.gd`, Node Name `LoggerInstance` (if not already present)
- Path `scripts/core/event_bus.gd`, Node Name `EventBus`
- Path `scripts/core/config.gd`, Node Name `GameConfig`
- Path `scripts/core/services.gd`, Node Name `Services`

Ensure the names match exactly; gameplay scripts reference these singletons.

### Usage Patterns

- Instead of `get_node("/root/LoggerInstance")`, prefer:
  - `var logger = Services.logger()`
- To broadcast gameplay events globally:
  - `Services.bus().emit_ammo_changed(self, ammo_current)`
  - `Services.bus().emit_player_health_changed(mount_hp, rider_hp)`
- UI should subscribe to `EventBus` where possible, and fall back to direct node signals when necessary.
- Type locals explicitly (example in GDScript):
  - `var player: Node = get_tree().get_first_node_in_group("players")`

### Contributing

- Read and follow `godotconventions.mdc`.
- Keep systems autonomous and signal-driven. Avoid hardcoded scene paths or deep tree walks.
- Prefer adding a new signal or a method on `EventBus` over introducing cross-node dependencies.
- If you need a shared thing, surface it via `Services` or `GameConfig` instead of adding more singleton lookups.

