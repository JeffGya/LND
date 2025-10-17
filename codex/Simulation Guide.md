
# Simulation Guide (MVP)

This sim focuses on two loops:
1) **Economy** — Ase yield vs. Ekwan pressure, modulated by Faith & Harmony.
2) **Emotion** — Morale decay under rising Fear.

## Determinism
We use a tiny PCG32 PRNG with a campaign seed so runs are reproducible.

## Extend it next
- Add **idle/active Ase** separation.
- Plug in **Realm reward** curve and **Ekwan drop%** from the Economic Model.
- Track **deaths** and feed **Legacy Fragments** into morale deltas.

> Tip: keep LLM text out of the core loop; treat it as cosmetic.
