# Working in this repo

Phoenix LiveView prototype for hospitality team communication. One workflow
carried end to end — an unexpected absence becomes a coordinated, multilingual
coverage response — rather than several shallow screens. See `README.md` for
what it does and why; this file is about how to change it.

## Commands

```bash
mix setup                # deps, database, migrations, seeds, assets
mix phx.server           # http://localhost:4000
mix test                 # creates and migrates the test DB first (~1s)
mix precommit            # compile --warnings-as-errors, unused deps, format, test
mix gettext.extract --merge   # after ANY new gettext string — see below
```

`mix test` runs in about a second. Run it after every change rather than
batching; there is no reason not to.

## Where things go

| The change involves | Goes in |
| --- | --- |
| A coverage rule or transition | `Sona.Coordination` |
| Task board behaviour | `Sona.Coordination.Tasks` |
| Rosters and who is on a shift | `Sona.Coordination.Shifts` |
| A line in the activity feed | `Sona.Coordination.Events.record/4` |
| Anything pushed to connected clients | `Sona.Coordination.Notifier` |
| Text a person typed | `Notifier.translate_content/2` — i18n comes free |
| Fixtures, personas, reset | `Sona.Demo` — **never** a context |
| A screen | `lib/sona_web/live/home_live/*.ex` + assigns in `HomeLive` |

## Rules that are easy to break

**Authorization lives in the context, not the template.** Every write takes an
explicit actor id and checks department, role and ownership against it. Hiding
a button is not a permission model — LiveView events are forgeable. When you
add a control, add the guard in the context and a test that the wrong persona
is not offered it.

**Seeding never goes in a context.** `Sona.Demo` is deliberately top-level: it
holds everything a real deployment deletes. Putting fixtures back into the
domain undoes the point of that split.

**A new PubSub message needs a `handle_info` clause in the same change.** Every
client subscribes to one topic, so a message with no matching clause takes the
LiveView down. Add both, or neither.

**New UI copy is not done until it is translated.** `mix gettext.extract --merge`,
then fill in `priv/gettext/{es,fr}/LC_MESSAGES/default.po`. An untranslated
string falls back to English and appears mid-sentence in a Spanish page —
the most visible possible bug in an app whose headline claim is multilingual.
Both catalogues are currently at zero untranslated; keep them there.

**Render state outside assigns will not re-render.** LiveView skips expressions
whose assigns did not change, so process-local or ambient state is invisible to
change tracking. That is why the language switch and the "show original" toggle
both use URL state plus `push_navigate` rather than a patch. If a change alters
*how* existing data renders rather than *what* data is there, reach for the URL.

**Tests must never touch the network.** `config/runtime.exs` is evaluated in
every environment, so it explicitly opts `:test` out of translation-provider
selection; without that, an API key in the shell silently replaces the stub and
the suite makes real calls from inside the Ecto sandbox. There are tests
asserting this. Do not undo it.

**Concurrency.** Coverage transitions go through `write_transaction/2`, which
takes `SELECT … FOR UPDATE` on the request row and re-checks preconditions
*inside* the transaction. New transitions use it too — do not read state, decide,
then write.

## Conventions

- Write functions return `{:ok, result}` or `{:error, reason}` with an atom
  reason (`:not_supervisor`, `:wrong_department`, `:request_closed`). The web
  layer maps reasons to flashes in `domain_error_flash/2`.
- Comments explain **why**, not what. If a line needs explaining because the
  obvious approach was wrong, say what was wrong with it.
- Test names are sentences describing the behaviour, not the function.
- Prefer a pure function of its inputs for anything time-dependent, so it can
  be tested by passing a timestamp rather than sleeping.

## Known state

- `Shift` uses UTC datetimes, so shifts crossing midnight work. `CoverageRequest`
  still uses date + time-of-day and does not — that migration is planned, see
  `docs/shifts-and-schedule-plan.md`.
- Messages is a static preview. Authentication does not exist; the persona
  switcher stands in for it and is the one deliberately fake thing.
- One global PubSub topic, and every client reloads on any change. Fine at this
  size, first thing to scope per-department when it is not.
