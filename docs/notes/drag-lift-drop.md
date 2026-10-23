# Drag, lift and drop: implementation notes

What it is for: you can pick Buddy up with the mouse, carry it, and let go.
Branch: `drag-lift-drop`. Code: `Sources/Carry.swift`, plus small changes in `Window.swift`, `Pet.swift`, `Model.swift`, `Avatars.swift` and each pet file.

```
press + move 4 px ──► grab()      Carry.held     window grows to 200×220, pet hangs from the pointer, swings
        │                         (own 30 Hz timer in .common run-loop mode)
release ──────────► letGo()      Carry.falling  a short drop (40 px) where you let go, never through the floor
        │
drop ends ────────► land()         Carry.landed   squash + bounce, landing words, per-pet pose
        │
landTime passes ──► putDown()    Carry.none     window back to small size, walking resumes
```

## Decisions (asked the user)

- Landing: first built as a fall to the bottom of the screen. After a live try, the user asked for a fall "kind of in place" (2026-10-18). Now it drops 40 px (`dropHeight`) where you let go, then squashes and bounces. Buddy stays at that height, as the old window drag did.
- Carry: the body swings behind the drag (a damped spring toward an angle from the drag speed, max 40°).
- Poses: one per pet. Words and timing are in each pet's `carried:` value.

| Pet | Lift | Landing |
|---|---|---|
| cat | scruff, limp, slow tail, "mrrp?" | lands, closes eyes, "lick lick" |
| pug | legs paddle, tongue out, "!!" | squash, "achoo!" |
| bear | sags, legs spread, "hmph" | floor shakes, dust |
| hero | flying pose | hero-landing crouch, floor shakes |
| ninja | curled ball, "!" | one flip in the drop, "HAI-YA!" |
| wizard | hat tips back, robe streams, "whoa!" | hat drops back on, ✨ |
| astronaut | floats, slow spin, "wheee" | slow fall (gravity 500 against 2600), dust |
| robot | arms up, antenna blinks, "beep?" | sparks, "clank", dazed, "beep!" |

## Decisions (mine)

- The window grows while held, so a swing or a word burst is never cut off at the window edge.
- The grip slides from the click point to the scruff over 0.2 s, so it looks picked up.
- `isMovableByWindowBackground` is now false. The old window drag would fight the new one.
- A plain click still works: `DragGesture(minimumDistance: 4)` starts only after 4 px of movement.

## Problems found while building

- **The swing did not move while held.** Cause: `Timer.scheduledTimer` runs only in the default run-loop mode, and macOS pauses that mode while the mouse button is down. Fix: the hold owns its own timer, added in `.common` mode.
  Same-bug search: all other `Timer.scheduledTimer` uses in `Window.swift` and `Model.swift`. None of them must run during a drag (session polls, bubbles, wander). They only wait until release. No change.
- **Hover hearts (💖) burst during the fall.** Cause: the 1.4 s hover timer in `Window.swift` fires while the pointer is on the pet. Fix: it adds a heart only when `m.carry == .none`.

- **Fresh review (separate agent) found 4 more. All fixed:**
  1. Buddy could stay held forever if SwiftUI cancels the drag (it does not call `onEnded` then). Likely trigger: a drag during the dance, because the view under the gesture changes on lift. Fix: while held, the tick lets go when the mouse button is up. Not checked live (no dance frames on this Mac).
  2. Each lift started with a false swing of about 9°: the drag speed compared the window x with the pet-box x. Fix: both use `petBox`. Live check after the fix: lift and hold still gives 0° to 1°. (I did not measure the old build live. The 9° is the reviewer's calculation.)
  3. The eyes aimed at the wrong point while carried: `blobCenter` used the small-window layout. Fix: it uses `petBox`.
     Same-bug search: every use of `panel.frame` with the old `- 8 - 84` layout math. Only `placeLitter` had it. It runs only when Buddy is not held, but now also uses `petBox`.
  4. After a fall away from a still pointer, `hovering` could stay true, so Buddy did not walk until the mouse moved. Fix: `putDown` clears it if the pointer is not on the pet. Not checked live.

- **Rebase onto main (43 new commits, 2026-10-18).** Main had moved the pet around the open card (`petSpot`, `petFrame`). Changes:
  - `petBox` now comes from `petFrame`. A grab clears `petSpot`, `placed` and `cardRect`, because the card closes when you lift Buddy.
  - `followDrag` stays. `wander` uses it after it puts a lost window back on screen, not only after the old window drag.
  - Two new buddies from main got their own lift and landing: Stitch ("eep!", ears out, arms up, "again!") and the chemist ("careful!", flask held level, "…stable.").
  - A new selftest check fails if a buddy has no lift or landing of its own. It failed for these two before I added them.

## How it was checked

- `./Buddy --selftest`: swing lags and settles, never more than 40°, fall lands on the floor, `floorBelow` picks the right screen, model states.
- `./Buddy --snapshot <dir>`: `carry-<pet>.png` for all 8 pets (held 0/+25/-25, falling, landed at 4 times).
- Live, with a test copy that saves the window to PNG 5 times a second and posts real mouse events (scratchpad scripts `instrument.sh`, `run.sh <pet>`, `drag`):
  - cat, robot, astronaut: lift words, swing from -40° to +40°, fall, landing words. Log: lift at 1431,240, drop at about 662,572, landed at y 80.
  - pug with the card open (`--card`): the card closes on grab, the drag works.
  - A click with no movement still does a trick (log shows `doGesture carry=none`).
  - Re-grab in mid-fall (astronaut, `MODE=regrab`): log shows `lift astronaut at 710,572 from falling`, then a new drop and landing.

## Known limits

- Live check of the short drop: cat only (let go at y 348, landed at y 308). The test moves the real pointer, so I stopped it while the user was at the laptop.

- The astronaut spins while falling and turns upright at once on landing (no ease).
- The session dots (•••) above the pet stay in place while it swings.
- Not checked live: two monitors (only `floorBelow` has unit tests).
