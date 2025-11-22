

# Purify Shrine — Combat Addendum (MVP)

This document describes how **Purify Shrine** stages function inside the **Combat Simulation Core**, complementing the existing Realm System documentation.

---

## 1. Shrine as a Combat Entity

During Purify Shrine stages, the shrine becomes a **combat participant**:

- **HP & Max HP** seeded from `GameBalance_Realm`.
- **is_shrine = true**
- **can_act = false** (never takes turns)
- Participates on the **allied team**.
- Is always targetable by enemies based on shrine‑focused AI.

The shrine is destroyed if `hp_current <= 0`, which immediately ends the wave and the entire stage as **failure**.

---

## 2. Shrine Damage Behavior

Enemies always prefer to target the shrine (MVP rule):

- The shrine takes normal damage using standard formulas.
- Damage may be scaled by `SHRINE_ENEMY_DAMAGE_MULTIPLIER` from `GameBalance_HeroCombat.gd`.

Additionally, shrine HP is drained **each combat round**:

- Base drain defined in `SHRINE_BASE_DRAIN_PER_ROUND`.
- Additional “stack” drains from Purify cooldown expirations:
  - Each Purify use applies a temporary reduction for a limited number of rounds.
  - After the reduction expires, a “stack expiry” drain tick occurs (configurable in `GameBalance_HeroCombat.gd`).

This creates constant pressure regardless of enemy performance.

---

## 3. Purify Action (Hero Ability)

Heroes gain access to a special action during Purify Shrine stages:

### Conditions for Availability
- Shrine HP < **50%**.
- Only one chosen “**designated purifier**” may use Purify per round.
- Purify has a per‑hero cooldown stored in combat state.
- Action type: `PURIFY_SHRINE`.

### Effects
- Does not affect enemies.
- Flags the shrine as **purified for this wave**.
- Applies a **temporary drain reduction** buff:
  - Duration: `SHRINE_PURIFY_STACK_ROUNDS`.
  - Reduction amount: `SHRINE_PURIFY_STACK_REDUCTION`.
- Once the stack expires, the shrine takes an additional “stack expiry drain.”

Purify **never restores health**, only slows the decline.

---

## 4. Purifier Assignment

For MVP, a purifier is automatically selected at wave start:

- Highest Faith score receives priority.
- “Devout” archetype heroes receive a weighting bonus.
- Logic is tunable via config weights:
  - `SHRINE_PURIFY_WEIGHT_FAITH`
  - `SHRINE_PURIFY_WEIGHT_ARCH_DEVOUT`

Only this hero will use Purify automatically.

---

## 5. Enemy AI Rules

Enemy target selection in shrine stages:

1. If shrine is alive → **target shrine**.
2. If shrine is destroyed → fallback to normal hero-target logic.

Post‑MVP room for strategies:
- Enemies alternating targets.
- Enemies that siphon HP.
- Tactics based on shrine HP thresholds.

---

## 6. Round Structure & Logging

Each combat round includes:

1. Turn order resolution.
2. Hero actions (Purify/Attack/Refuse).
3. Enemy actions (always targeting shrine).
4. Shrine drain application.
5. Morale/fear ticks.
6. End-of-round shrine survival check.

Logs include:
- shrine damage from enemies
- shrine drain ticks
- Purify usages and cooldowns
- shrine destruction summary

Example line:

```
Esi Nkrumah PURIFY_SHRINE → Shrine  (cd=3)
[shrine] Drain reduced via Purify (reduction=2, duration=4)
```

---

## 7. Wave Resolution (ObjectiveRunner)

After each wave, the shrine state is returned to the realm layer:

- shrine_hp_after_wave
- wave_purified
- waves_cleared
- shrine_destroyed
- purify_uses_this_wave

ObjectiveRunner determines stage success:

- **Success:** shrine survives all waves.
- **Failure:** shrine destroyed or party wipe.

Rewards and realm progress are handled as usual.

---

## 8. Balance Knobs (Config Summary)

`GameBalance_HeroCombat.gd`
- `SHRINE_BASE_DRAIN_PER_ROUND`
- `SHRINE_ENEMY_DAMAGE_MULTIPLIER`
- `SHRINE_PURIFY_COOLDOWN_ROUNDS`
- `SHRINE_PURIFY_STACK_ROUNDS`
- `SHRINE_PURIFY_STACK_REDUCTION`
- `SHRINE_PURIFY_WEIGHT_FAITH`
- `SHRINE_PURIFY_WEIGHT_ARCH_DEVOUT`

`GameBalance_Realm.gd`
- shrine base HP
- number of waves
- rewards
- realm-tier difficulty scaling

---

## 9. Future Extensions (Post-MVP Notes)

- Allow player to choose the purifier via UI.
- Shrine-only buffs from specific classes.
- Tactical enemy variants (leechers, corrupters).
- Dynamic realm-modified shrine behaviors.
- Over-purification penalties (bonus wave, lore events).

---

End of file.