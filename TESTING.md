# Cursive ClassicAPI edition: outstanding in-game tests

Tests that need a busy raid, another class, or another player. Tick each one (`[x]`) when the situation comes up and
the result is right. If one fails, note what you saw under it and report it.

Everything not listed here has been tested in game.

## Busy raid fights

- [ ] No Lua errors in BugSack during a long, busy raid fight. The combat-log handler (batch 3, `6f5441c`) runs on every
      combat event.
- [ ] Your debuff timers on a boss carrying many debuffs stay right, and an icon goes away if your debuff is pushed off.

## Another player of the same class

- [ ] Another player's copy of one of your debuffs (e.g. another priest's Shadow Word: Pain) runs out or is dispelled on
      a mob that also has yours: your icon stays.

## Another druid (batch 5)

- [ ] With "Shared Faerie Fire" on, another druid's Faerie Fire shows greyed out with the same time left as the
      target frame, and stays right when they refresh it (including a resisted refresh).
- [ ] Your own Faerie Fire on the same mob stays in colour.

## Priest

- [ ] With Improved Shadow Word: Pain, SW:P shows 24 s and matches the target frame.

## Warlock

- [ ] Corruption, Curse of Agony and Siphon Life timers match the target frame within a few tenths of a second.
- [ ] Conflagrate cuts 3 s off Immolate's timer.
- [ ] Dark Harvest still makes the DoT timers count down faster while channelled.
- [ ] Malediction setting (batch 5): with it on, `/cursive curse Curse of Recklessness|target` doesn't cast while your
      Curse of Agony is up; with it off, it does. `malediction=1` / `malediction=0` in the command override the setting.

## Druid

- [ ] Rip at 1 and at 5 combo points, without the Idol of the Black Morass: timers match the target frame.
- [ ] Rip with the Idol of the Black Morass equipped: 10% shorter, using Cursive's own calculation.
- [ ] Ferocious Bite with a Carnage proc refreshes Rip and Rake (without the idol). With the idol, a Carnage refresh of
      Rip is not shown; that is expected.
- [ ] Rake, Moonfire and Insect Swarm timers match the target frame.
- [ ] A bleed-immune mob drops Rake after about 1 s.

## Rogue

- [ ] Rupture and Kidney Shot at different combo points: timers match the target frame.
- [ ] Gouge, with Improved Gouge if talented.

## Shaman

- [ ] Molten Blast refreshes Flame Shock's timer.

## Other addons

- [ ] Kui_Nameplates_Auras with its Cursive option on: nameplate debuff icons from Cursive still show.
- [ ] SuperCleveRoidMacros' Cursive conditionals (`[cursive]`-style checks) still work in your macros.

## Optional: without SuperWoW

SuperWoW is optional since 3.2.0, but Cursive hasn't been run without it.

- [ ] With SuperWoW disabled: hovering a bar shows the tooltip, clicking a bar targets the mob, and commands cast on the
      chosen mob. If any of these fail, the README's "SuperWoW is no longer required" line needs correcting.
