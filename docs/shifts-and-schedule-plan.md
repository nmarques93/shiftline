# Plan: coupling tasks to shifts, and a department schedule

Status: proposal. Written in response to customer requests for a tighter link
between tasks and shifts, plus a calendar view of both.

---

## 0. The decision that comes first

**Does Shiftline author shifts, or consume them?**

Nothing else in this plan can be settled until this is. The market analysis this
product was built on positions Shiftline as a *frontline response layer that sits on
top of existing systems*, explicitly not "another hotel management system". Every
serious customer already has a rota somewhere — Actabl, Deputy, 7shifts, Fourth,
or a spreadsheet. If we let people build rotas here we acquire availability
rules, time-off, labour cost and overtime compliance, and we are competing with
the incumbent on its own ground with none of its history.

**Recommendation: consume, with manual entry as a fallback.** `Shift` is modelled
from day one as something that can be synced — it carries `source` and
`external_id` — and manual creation is the path for customers with no WFM system
rather than the primary experience.

This satisfies the request in full while keeping the differentiator: we are the
layer that makes a shift *respond* when something goes wrong, not the layer that
decides who works it.

Non-goals, to be restated whenever this expands: rota authoring as the primary
flow, availability and time-off, labour cost, payroll, auto-assignment,
multi-property scheduling.

---

## 1. What is already true

A shift exists in the schema today — it is just smeared across two tables and
duplicated rather than named:

| Table | Shift-shaped columns |
| --- | --- |
| `coverage_requests` | `department`, `role`, `shift_date`, `start_time`, `end_time`, `location` |
| `shift_tasks` | `department`, `shift_date`, `due_time`, `location` |

Consequences worth naming: the two cannot be joined, "the evening shift" is not
addressable, and the Today strip renders a hardcoded `14:00–22:00` because there
is nothing to read it from. This work therefore *removes* duplication rather than
adding a concept.

---

## 2. Model

Two entities, and the split matters.

**`Shift`** — a department's block of covered time.

    id, department, role, starts_at (utc_datetime), ends_at (utc_datetime),
    location, source ("manual" | "import"), external_id, timestamps

**`ShiftAssignment`** — who is working it.

    id, shift_id, staff_member_id, status ("scheduled" | "absent" | "covering"),
    timestamps
    unique index (shift_id, staff_member_id)

### Why a shift is not per-person

The tempting simplification is one row per person per shift. It breaks on two
things the app already does:

- **Unassigned work.** "Restock the welcome desk stationery" is seeded
  deliberately unassigned so a frontline member can claim it. If a shift were
  per-person, that task would have no shift to belong to.
- **Coverage is a shift needing a person.** The shift has to exist independently
  of who is on it, or a request to fill it has nothing to point at.

So the shift is the window, and assignment is a separate fact about it. This also
gives absence a natural home: an assignment flipped to `absent` is what triggers a
coverage request, instead of a free-text `absent_name`.

### Times are UTC datetimes, not date + time

`Shift` uses `starts_at` / `ends_at` as `utc_datetime` from the first migration.
The seeded roster already contains a **Night Auditor**, so shifts crossing
midnight are implied by the domain we ship. A `shift_date` + `Time` model makes
22:00–06:00 either unrepresentable or silently wrong, and the existing
`validate_shift_window` (`end_time` must be after `start_time`) rejects it
outright.

Getting this right in a new table costs nothing. Retrofitting it later means
migrating data and rewriting the same code twice.

---

## 3. Coupling tasks

Add `shift_id` to `shift_tasks`, **nullable**.

- `shift_id` present — the task belongs to that shift and inherits its department,
  window and location.
- `shift_id` null — a department errand not tied to a block of time. This is
  today's behaviour and stays valid; `department` and `shift_date` remain as the
  fallback so nothing regresses.

Keep `department` denormalised on the task even when `shift_id` is set. It is the
column every authorization check reads (`Tasks.list/2`, `assignable_staff/1`,
every guard in `Shiftline.Coordination.Tasks`), and making those joins-through-shift
would spread the department rule across two tables for no benefit.

`due_time` becomes `due_at` (utc_datetime) in the same pass, validated to fall
within the parent shift when there is one.

**Immediate visible win:** the Today strip stops lying. `14:00–22:00` and
`Lobby` are read from the staff member's actual assignment.

---

## 4. Coupling coverage

Add `shift_id` to `coverage_requests`, **keeping `start_time`/`end_time`**.

This is deliberate and worth understanding before touching it: acknowledging a
*partial* offer opens follow-up requests for the uncovered remainder, so a
request's window is frequently **narrower than its shift**. The shift is the
parent; the request carries the window it actually needs filled.

`department`, `role` and `location` become derivable from the shift and should be
dropped from the request once backfill is complete.

`absent_name` (free text) is superseded by the assignment flipped to `absent`,
which turns "Jordan Lee" from a string into a person the system can reason about —
notify, exclude from eligibility, show on the schedule as a gap.

---

## 5. The schedule page

A fifth tab, department-scoped, day and week views.

**Authorization reuses what exists.** Scope is the same department rule as
`Tasks.list/2` and `eligible_staff/1`. No new visibility concept is introduced;
if that rule is wrong it is wrong in one place.

**URL as state**, consistent with the rest of the app:

    /?view=schedule&role=supervisor&date=2026-08-18&range=week

That keeps it shareable, refresh-safe, and demoable side by side like everything
else here.

**Reads.** One windowed query for shifts in range, preloading assignments, staff
and tasks. The N+1 risk is real: a week view is ~35 shifts, and a query per shift
for tasks is how this gets slow. Assert the query count in a test.

**By role.** Supervisor sees every assignment plus uncovered gaps and open
coverage requests inline — the gap *is* the thing they are looking for. Frontline
sees their own shifts prominent with department context around them.

**Real-time needs topic granularity first.** Today there is one global PubSub
topic and every client re-runs a full data load on any change. A week view
subscribed to that would reload thirty-five shifts because someone ticked off a
task. Introduce `"department:#{name}"` topics as part of this work, and use
`stream_insert` rather than a wholesale refresh.

**Localized dates are a genuine gap.** `today_line/0` uses
`Calendar.strftime(date, "%A, %B %-d")`, which emits English weekday and month
names regardless of locale — invisible today because dates appear once, glaring
on a calendar. Needs a localized formatter (`ex_cldr_dates_times`, or a Gettext
lookup table for seven weekdays and twelve months). Do not ship the page without
it; multilingual is this product's headline claim and a calendar is where a
reviewer would look.

---

## 6. Sequencing

Each phase is shippable on its own.

| # | Phase | Notes | Est. |
| --- | --- | --- | --- |
| 0 | Decide sync vs author | Blocks the schema. Product call, not engineering. | — |
| 1 | `Shift` + `ShiftAssignment`, seeds, `Shiftline.Coordination.Shifts` context | UTC datetimes from the start | ~1d |
| 2 | Couple tasks; Today strip reads a real shift | Nullable FK, no behaviour lost | ~0.5d |
| 3 | Couple coverage; assignment replaces `absent_name` | Touches the state machine and follow-ups — most care needed | ~1d |
| 4 | Convert `coverage_requests` to UTC datetimes | Overnight support; touches every time helper and its tests | ~1.5d |
| 5 | Schedule page + department PubSub topics + localized dates | | ~2d |
| 6 | First import adapter behind a behaviour | Mirrors `Shiftline.Translation`'s adapter pattern | ~1.5d |

Roughly **1.5–2 weeks** for one engineer. Phases 1–3 alone deliver the coupling
customers asked for; 5 delivers the calendar.

**Migration mechanics** for each coupling step: add the FK nullable, backfill from
the existing denormalised columns, dual-read behind a function, then enforce
`NOT NULL` and drop the superseded columns in a later migration. No single
deploy both writes and requires the new shape.

---

## 7. Testing

Keep the derived rules **pure functions of `(shift, range)`** — does this shift
fall in this week, does it cross midnight, does this task's `due_at` sit inside
its shift, which shifts have no assignment. Time-based logic is usually tested
badly with sleeps and mocked clocks; passing the boundary in as an argument makes
all of it ordinary unit testing.

Specific cases that must exist before phase 4 is called done: a 22:00–06:00 shift
is representable, sorts correctly, and reports the right duration; a task due at
01:00 belongs to the shift that started the previous evening; a week query
straddling a DST change returns the right set.

---

## 8. Open questions

1. **Which WFM system first?** Actabl is the strongest competitor for coverage
   specifically, so integrating with it is either the sharpest wedge or the worst
   idea. Needs a commercial answer, not a technical one.
2. **Do shifts recur?** A recurring pattern is a rota-authoring feature and sits
   the wrong side of the non-goals above. Prefer importing generated instances.
3. **Property time zone.** Phase 4 assumes one zone per property. Multi-property
   customers need it on the property, which does not exist as an entity yet.
4. **What happens to a shift's tasks when the shift is covered by someone else?**
   Current assumption: tasks stay with the shift, not the person, which is the
   main practical argument for coupling them in the first place.
