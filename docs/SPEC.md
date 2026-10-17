# Avo: product spec (v1)

Avo is a macOS menu bar app. A cheerful avocado coach pops up while you work and asks for one small stretch. Change this file when behaviour changes.

## Principles
- One nudge, one move, under 2 minutes.
- Never steal focus, never interrupt calls, never nag.
- Everything stays on the Mac. No account, no network, no analytics.

## States
| # | State | What the user sees |
|---|-------|--------------------|
| 1 | Paused | Nothing. Menu bar icon shows paused. |
| 2 | Working | Nothing. Active time accumulates. |
| 3 | Away | Nothing. No input for 5 min. Work timer resets (being away counts as a break). |
| 4 | Quiet | Nothing. Camera or mic in use, a full-screen app in front, screen sharing, or outside work hours. A due nudge waits until 1 min after Quiet ends. |
| 5 | Shows up | Card slides in at the top right (design: Flow step 1). |
| 6 | In progress | Countdown, rep counter, progress bar (Flow step 2). |
| 7 | Done | Celebration with today's count (Flow step 3). |
| 8 | Snoozed | Short confirmation (Flow step 4), then hidden until the snooze ends. |
| 9 | Left alone | Card shrinks into a pill at the screen edge (Flow step 5). |

## Actions
- Card: **Start**, **Later**, **How to** (expands step instructions with Avo's pose).
- In progress: **Done**, **Stop**.
- Snooze confirmation: **Actually, now**.
- Pill: **Start**, **✕ dismiss** (needs design).
- Menu bar menu: Nudge me now, Pause 1 hour, Pause until tomorrow, today's count and streak, Settings, Quit.

## Timing and logic (defaults, all configurable)
- First nudge after **25 min of active work**. Active = keyboard or mouse input within the last 2 min.
- Card stays **60 s**, then becomes the pill.
- Pill ignored for **10 min** = nudge skipped, work timer restarts.
- **Later** snoozes **10 min**. The third Later in a row skips the nudge.
- **Stop** = no credit, work timer restarts.
- **Done** = celebrate **3 s**, auto close, +1 to today's count, work timer restarts.
- Snooze confirmation shows **2 s**.
- Rep counter is paced by a timer (about 3 s per rep). The app cannot see reps.
- Exercise choice: rotate through enabled moves, never repeat one of the last 2, Walkabout at least every 3rd nudge.
- Daily goal **6**. Streak = consecutive work days with the goal reached.
- Work hours **Mon to Fri, 9:00 to 19:00**.
- Sound **off** by default.

## Exercises
| id | Name | Cue | Dose | Pose art | Face |
|----|------|-----|------|----------|------|
| chinTuck | Chin tucks | Pull your chin straight back. Eyes stay level. | 10 slow reps | avo-chinTuck | focus |
| neckSide | Neck side stretch | Ear toward shoulder. Let the other shoulder sink. | 20 sec each side | avo-neckSide | calm |
| shoulderRoll | Shoulder rolls | Big slow circles, rolling backward. | 10 reps | avo-shoulderRoll | happy |
| thoracic | Upper back opener | Hands behind your head, lift your chest over the chair back. | 8 reps | avo-thoracic | grin |
| reach | Overhead reach | Fingers laced, push the ceiling away. | 3 holds of 10 sec | avo-reach | happy |
| lookFar | Eye break | Look at something about 20 feet away. | 20 sec | avo-lookFar | focus |
| walk | Walkabout | Stand up, refill your water, take a lap. | 2 min | avo-walk | happy |
| breathe | Slow breaths | In for 4, out for 6. Shoulders stay low. | 5 breaths | avo-breathe | calm |

State art: Shows up = avo-wave, Done = avo-cheer, Snoozed = avo-snooze, Pill = face crop of avo-idle.

## Settings screen
Interval, work hours and days, daily goal, exercises on or off with editable doses, snooze length, sound, launch at login.

## Copy (voice: upbeat, short, never guilt)
- Card header: "Coach Avo"
- Done: "Nice one!" / "<Exercise> done. That makes <n> today."
- Snoozed: "No stress" / "I will check back in <n> minutes."
- Pill: "<Exercise> waiting"

## Open decisions
- None right now.

## Behaviour details
- **Pill dismiss ✕**: a 20 pt circle in the light button colour on the pill's top-left corner, shown on hover. Dismiss = nudge skipped, work timer restarts.
- **App icon**: Avo on a tile-green rounded square (`design/art/app-icon.png`).
- **How to** copy: three short steps per move (`steps` in `Avo/Model/Exercise.swift`), shown with the move's pose.
- **In progress at 0:00**: the card stays until Done or Stop and the "left" label reads "Tap Done". No automatic credit, so the Walkabout works when you are away from the keyboard.
- **Rep counter labels**: "Rep n of N" (reps), "Side n of 2" (each side), "Hold n of N" (holds), "Breath n of N" (breaths); timed moves show the dose.
- **Quiet counts as work**: time on a call counts toward the next nudge and never as Away. A full-screen app also counts, unless there has been no input for the Away time (then it is Away). The nudge waits and shows 1 min after Quiet ends. The screen saver and lock screen are not full-screen apps.
- **Sleep is a break**: if the Mac slept for at least the Away time, the work timer restarts and a snoozed nudge is dropped.
- **Menu shows why Avo is quiet**: e.g. "Quiet: microphone in use", so a stuck camera or mic is easy to spot.
- **A card on screen hides when Quiet starts** and returns 1 min after it ends. A card from "Nudge me now" ignores Quiet, Pause and work hours, and so does its snooze (it comes back at the promised time).
- **Away cancels a snoozed nudge** (a break is a break).
- **Outside work hours resets the work timer**, so the first nudge of the day comes 25 min into the day.
- **Pausing closes any card and restarts the work timer.**
- **The card stays while the pointer is over it**; its 60 s start again when the pointer leaves or How to is opened.
- **A waiting move that was turned off in Settings** is swapped for another when the nudge shows.
- **Screen sharing** is not detected (no public API); calls are caught by the camera and mic check.
- **Sound** (when on): the system "Glass" sound when a card shows up.
