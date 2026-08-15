# Sona Prototype Implementation Plan

## Recommendation

Build a single-screen Phoenix LiveView prototype focused on one closed-loop coverage incident:

`absence reported -> eligible staff notified -> response received -> replacement approved -> handoff acknowledged`

Do not attempt to model a full hotel platform. The brief and market research point to the differentiator being an operational response layer, not scheduling, payroll, PMS, or general-purpose chat. A narrow, high-fidelity workflow communicates that value more effectively than several shallow screens.

The prototype supports two perspectives in the same app:

- **Supervisor (Maya):** sees the active incident, candidate responses, approval controls, and viewed/responded/acknowledged status.
- **Frontline staff member (Luis):** sees a localized urgent request and can accept, decline, offer partial coverage, ask a question, and acknowledge the handoff.

A visible role switcher lets the evaluator move through both sides of the workflow without authentication. Because the current tab, persona, and focused incident live in the URL (`?view=coverage&role=frontline&request=5`), two browser windows can watch the same incident from both sides simultaneously.

There can be more than one open incident at a time — a mid-shift partial offer resolves into two follow-up gap requests — so Today lists every active request, the nav badges show the real count, and the Coverage board focuses one incident with an "other open requests" switcher beneath it.

## Stack

> **Revision note.** An earlier draft of this plan recommended a client-only React + Vite prototype with in-memory fixtures. The build pivoted to Phoenix LiveView, and the plan below reflects what was actually built. The reasons for the pivot:
>
> 1. **Real-time visibility is the product's core claim.** "Has the team seen the update?" only demos convincingly when a response in one window updates the supervisor's board in another. LiveView + Phoenix PubSub gives that for a few lines of code; a client-only SPA can only fake it inside one tab.
> 2. **The workflow is a server-side state machine.** Guarded transitions, an auditable activity trail, and per-staff response records are naturally an Ecto schema + context, and the state survives refreshes instead of resetting.
> 3. **One language for domain and UI** keeps the prototype small: no API layer, no client state library, no duplication of types.
>
> The trade-off — needing Postgres locally instead of `npm run dev` — is acceptable for an evaluated case study and documented in the run commands below.

- **Phoenix LiveView:** server-rendered, stateful UI with PubSub-driven live updates and URL-based navigation (`push_patch`).
- **Ecto + PostgreSQL:** the coverage workflow as an explicit, constraint-backed state machine (`open -> contacting -> claimed -> approved -> resolved`).
- **Gettext + a translation service:** UI copy is localized with Gettext, keyed on each staff member's preferred language and applied to the workflow itself (request, actions, statuses, responses, flashes), not just settings — English, Spanish and French catalogs ship. *User-entered* content — what a supervisor types into a request, a response note, a question, an activity line carrying real names and times — cannot be a Gettext msgid, so it goes through `Sona.Translation`: a cache in front of a pluggable provider. See "Translating what people type" below.
- **Plain CSS with variables (plus the stock Tailwind pipeline):** a distinctive visual system without UI-library defaults.
- **Seeded demo data:** one realistic hotel and incident, with a twelve-person roster across two departments (Front Office and Housekeeping) in mixed languages and response states. The second department is there so department-scoped eligibility is visible rather than theoretical — a Housekeeping request never reaches the front desk. `Reset demo` restores the starting point.

## Product Shape

A responsive application shell with:

- A compact hotel/team identity area and role controls.
- A left navigation rail on desktop and bottom navigation on mobile: **Today**, **Coverage**, **Messages**, **Profile**.
- A prominent status-oriented main canvas rather than an infinite chat feed.
- An incident detail panel on the Coverage tab with the step trail, localized response actions, and the team response board.

The main visual hierarchy answers the brief's success criteria immediately:

1. What needs attention now?
2. What is the current coverage status?
3. Who owns the next action?
4. Has the team seen and acknowledged the update?

Warm hotel neutrals with one high-contrast operational accent, large status labels, clear timestamps, and generous touch targets. Every meaningful message exposes an action or state, not just chat content. Messages and Profile are deliberately shallow previews so they do not compete with the coverage story.

## Structure

```text
lib/
├── sona/
│   ├── coordination.ex            # context: the coverage state machine, and only that
│   ├── demo.ex                    # fixtures + the persona switcher standing in for auth
│   ├── coordination/
│   │   ├── tasks.ex               # the shift task board
│   │   ├── events.ex              # the activity feed and the sentences in it
│   │   ├── notifier.ex            # the PubSub contract clients subscribe to
│   │   ├── staff_member.ex
│   │   ├── coverage_request.ex    # status state machine lives here + in the context
│   │   ├── coverage_response.ex   # includes "pending" = viewed but not answered
│   │   ├── activity_event.ex
│   │   └── shift_task.ex
│   ├── translation.ex             # cache in front of a pluggable provider
│   └── translation/
│       ├── prompt.ex              # the instruction every provider shares
│       ├── local.ex               # offline default
│       ├── deepseek.ex
│       └── claude.ex
└── sona_web/
    └── live/
        ├── home_live.ex           # shell, URL state, event handlers, PubSub subscribe
        └── home_live/
            ├── ui.ex              # shared cards, icons, formatting helpers
            ├── today.ex
            ├── coverage.ex
            ├── messages.ex
            └── profile.ex
test/sona/coordination_test.exs    # state machine + PubSub coverage
priv/gettext/es/LC_MESSAGES/default.po
```

Boundaries that matter: all writes go through `Sona.Coordination` or `Sona.Coordination.Tasks`, which validate the transition, record an activity event naming the real actor, and broadcast through `Sona.Coordination.Notifier`; the LiveView only renders state and dispatches actions.

`Sona.Demo` sits outside the domain on purpose. Everything a real deployment would delete — seeded fixtures, the reset button, and a persona switcher that hands out an identity with no proof of who is asking — lives there, so the line between what is real and what is scaffolding is visible in the module tree rather than in a comment. Authentication replaces `Sona.Demo.personas/0` and nothing else: every write function already takes an actor id and already checks department, role and ownership against it.

## Data Model

- `StaffMember`: name, role, department, preferred language, supervisor flag.
- `CoverageRequest`: department, role, date, shift window, location, urgency, reason, handoff note, status, selected replacement, acknowledgement timestamp.
- `CoverageResponse`: one row per staff member per request (unique index), typed `pending | accepted | partial | declined | question`, with separate `viewed_at` and `acknowledged_at` — so *seen*, *responded*, and *acknowledged* are three distinct facts. Partial offers carry a structured covered window (`cover_start_time`/`cover_end_time`, validated against the shift), so approving one never pretends the shift is whole: `coverage_gaps/2` computes the uncovered remainder and the UI shows **Partially covered** plus the gap that still needs coverage.
- `ActivityEvent`: kind, actor, body — the incident's audit trail.

Transitions are enforced in the context and return `{:ok, _}` / `{:error, reason}`:

- `respond/4` — only while the request is active; an offer moves it to `claimed`; partial offers require a valid window inside the shift.
- `approve/3` — requires an active request and an actual offer from the chosen person; records the approver.
- `acknowledge_handoff/2` — only from `approved` and only by the approved replacement; resolves the request, and if the approved offer was partial, automatically opens a follow-up coverage request for each remaining gap so a shift is never silently closed while uncovered.
- `ask_question/3` — a question is a message, not a coverage answer: it records an activity event and marks the asker as having viewed, but never overwrites an existing offer, so asking "which desk?" after accepting cannot strand the request with nobody approvable.
- `mark_viewed/2` — opening the request as frontline staff feeds the supervisor's viewed count.

Every transition takes a `SELECT … FOR UPDATE` lock on the request row and re-checks its own preconditions *inside* the transaction, so two supervisors approving at once cannot both win, and a double acknowledgement cannot produce duplicate follow-up requests.

## Translating What People Type

Gettext covers strings that exist at compile time. It cannot cover the sentence a supervisor types at 06:00, so localization is split in two:

- **UI copy** → Gettext catalogs, resolved per staff member's preferred language.
- **User-entered content** → `Sona.Translation`, a cache in front of a provider behind a behaviour.

The shape matters more than the provider:

- **Translation happens on write, not on read.** When someone creates a request, answers with a note, asks a question, or an activity line is recorded, the text is fanned out to every supported locale in a supervised background task and cached in `content_translations`, keyed by a hash of the text. Rendering is then a single indexed read — a page render never waits on a network call, and the same sentence is never paid for twice.
- **The result arrives live.** The fan-out broadcasts on completion, so a window already showing the incident re-renders in its own language a moment later without a refresh.
- **The provider is a behaviour with three implementations.** `Sona.Translation.Local` (the default) is offline and deterministic, backed by the Gettext catalogs — the demo runs with no API key and identical output every time. `Sona.Translation.DeepSeek` and `Sona.Translation.Claude` each call their provider's HTTP API with Req (neither has an official Elixir SDK) and translate anything; whichever of `DEEPSEEK_API_KEY` / `ANTHROPIC_API_KEY` is present selects one. A test stub keeps the suite offline.
- **Swapping providers cannot change the ask.** Both hosted adapters send the same system prompt from `Sona.Translation.Prompt`, so the choice between them is a cost and latency decision rather than a behavioural one. DeepSeek defaults to the cheaper `deepseek-v4-flash`: this path runs once per locale per piece of user-entered text, so it is the cost that scales with usage, and translating one operational sentence is mechanical work.
- **Failure is visible, not invented.** If a provider can't translate something, nothing is cached and the reader sees the original text under a "shown in its original language" note, rather than a silent fallback that looks like a translation.

Because the source language is whatever the writer used, text is translated into *every* locale including English — so a question typed in Spanish reaches the supervisor in English, not just the reverse.

## Profile And Settings

Profile separates two kinds of facts, which is a deliberate product decision rather than a scoping shortcut:

- **Operator-managed, read-only:** name, role, department, property. In a workforce product these are administratively controlled, and since `approve/3` gates on `is_supervisor`, a self-service form that could write them would be a privilege escalation. `StaffMember.settings_changeset/2` simply does not cast those fields, so a crafted submission cannot reach them — there is a test for exactly that.
- **Worker-controlled, editable:** preferred language and in-app alerts.

Making language editable is what turns "localization is part of the workflow" from a claim into a demonstration: previously language was welded to persona (Luis was the Spanish speaker), so a reviewer could only compare two different people. Now the same supervisor can be switched to French and the entire operational surface — request, response labels, statuses, step trail, counts, flashes, translated content — follows, while identity stays put.

Notification preferences are deliberately narrow: in-app alerts are the only delivery channel this prototype actually has, so that is the only one stored and honoured (muting it empties the feed and hides the pip, it does not merely hide a dot). Push and SMS appear as explicitly disabled with a "not available in this prototype" note, rather than as switches that would quietly do nothing.

Saving settings re-mounts the LiveView rather than patching it, because gettext strings that do not reference an assign compile into the *static* half of the diff and are never re-sent on a patch. The same applies across windows: a settings change broadcasts `{:settings_updated, staff_id}`, and any other window showing that person re-mounts so its layout is re-rendered in the new language.

## Demo Walkthrough

0. As Maya, open **Coverage → New coverage request** and report an absence (department, role, time, location, urgency). It becomes the live incident — this is step 1 of the brief's primary scenario. The seeded incident exists so the app has something to show on first load, not because requests cannot be created.
1. Land on **Today** as Maya: every open coverage request, current shift, tasks, and team activity.
2. Open **Coverage**: structured incident facts, the step trail, and the response board (partial offer, decline, one viewed-only).
3. Switch to Luis (or open a second window with `?role=frontline`): the same request fully in Spanish, with accept / partial / decline / ask-a-question actions.
4. Accept the shift; watch the supervisor window update live.
5. As Maya, approve Luis — the request becomes **Approved** and the resolved card shows the handoff note.
6. As Luis, acknowledge the handoff — the request resolves and Maya sees the acknowledgement. (If the approved offer was partial, a follow-up request for the uncovered window opens automatically and the workflow starts again on it.)
7. **Reset demo** restores the starting state for the next run.

## Local Run Commands

Requires Elixir and a local PostgreSQL accepting `postgres/postgres` on `localhost` (see `config/dev.exs`).

```bash
mix setup
```

```bash
mix phx.server
```

Open http://localhost:4000. To see the two-way live demo, open a second window at http://localhost:4000/?view=coverage&role=frontline.

Verification:

```bash
mix test
```

## Definition Of Done For The Prototype

- A reviewer understands the active operational problem within five seconds of landing on Today.
- The coverage request identifies department, role, time, location, urgency, and current status.
- A staff member can respond without leaving the incident context, in their preferred language.
- The supervisor sees viewed/responded state per person and can approve a replacement — and the approval is rejected for anyone who has not actually offered.
- The resolved state visibly updates the handoff, and acknowledgement status flows back to the supervisor.
- Changes propagate live between two open windows via PubSub.
- English and Spanish are both represented in the actual request workflow, not only in Profile.
- The layout remains usable at a narrow mobile width and a supervisor-sized desktop width.
- The workflow's state machine is covered by tests, including its illegal transitions.
- Refresh is safe (state is in Postgres); `Reset demo` is the explicit way back to the starting point.
