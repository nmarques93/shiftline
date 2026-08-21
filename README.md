# Shiftline

A Phoenix LiveView prototype for hospitality team communication: how a hotel team can replace fragmented WhatsApp coordination with a visible, localized, two-way workspace.

It goes deep on one operational scenario rather than shallow on many — **finding coverage when a front desk employee is unexpectedly unavailable**, from the absence being reported to the handoff being acknowledged:

```text
absence reported → eligible staff notified → response received → replacement approved → handoff acknowledged
```

The brief's differentiator is an operational *response layer*, not scheduling, payroll, PMS or general-purpose chat. One high-fidelity workflow makes that case better than several shallow screens.

## Running it

Requires Elixir 1.17+, Erlang/OTP, and a local PostgreSQL accepting `postgres/postgres` on `localhost:5432` (see `config/dev.exs`). Node is not needed at runtime.

[`.tool-versions`](.tool-versions) pins Elixir 1.19.5 / Erlang 27.3.3 — what this was built and tested against. If you use asdf or mise it will pick those up automatically, and CI reads the same file so the two cannot drift.

```bash
mix setup
```

```bash
mix phx.server
```

Then open <http://localhost:4000>.

## The demo

Two switchable perspectives stand in for authentication:

- **Maya Chen** — Front Office Supervisor
- **Luis Garcia** — Front Desk Agent, Spanish preference

1. Land on **Today** as Maya: every open request, the current shift, the task board, and team activity.
2. Open **Coverage**: structured incident facts, the step trail, and the response board — a partial offer, a decline, and one person who has viewed without answering.
3. Report a new absence via **New coverage request** (department, role, time, location, urgency). A seeded incident exists so there's something on screen at load, but requests are created here — they are not fixtures.
4. Switch to Luis: the same request fully in Spanish, with accept / partial / decline / ask-a-question.
5. Respond, then switch back to Maya and approve him. Approve appears only next to a genuine offer — the person who declined has no button.
6. As Luis, acknowledge the handoff — the request resolves and Maya sees the acknowledgement.
7. Open **Messages**: the Front Office channel, a direct line to every colleague, and a pinned urgent announcement. Post as Maya, switch to Luis, and the channel shows it translated with the acknowledgement still outstanding.

If the approved offer was **partial**, the shift is never shown as fully covered: `coverage_gaps/2` computes the uncovered remainder and a follow-up request opens automatically for each gap, so the workflow starts again on what's left.

**Reset demo** restores the starting state.

### Watching it update live

The current tab, perspective and focused incident are URL state, so the workflow can be watched from both sides at once. Keep the supervisor view in one window and open a second at:

```text
http://localhost:4000/?view=coverage&role=frontline
```

A response in one appears in the other immediately. Read and response counts are pushed over PubSub, not polled.

## Multilingual behaviour

Language follows each person's own preference, set in **Profile**, and applies to the workflow itself — request, actions, statuses, step trail, counts, flashes — rather than only to a settings screen. English, Spanish and French ship as catalogs.

Localization splits in two, because Gettext can only cover strings that exist at compile time and cannot cover the sentence a supervisor types at 06:00:

- **UI copy** → Gettext, resolved per staff member's language.
- **User-entered content** → `Shiftline.Translation`, a cache in front of a provider behind a behaviour.

The shape matters more than the provider:

- **Translation happens on write, not on read.** New text is fanned out to every locale in a supervised background task and cached in `content_translations`, keyed by a hash of the text. Rendering is a single indexed read — a page render never waits on a network call, and the same sentence is never paid for twice.
- **The result arrives live.** The fan-out broadcasts on completion, so a window already showing the incident re-renders in its own language a moment later.
- **Failure is visible, not invented.** If a provider can't translate something, nothing is cached and the reader sees the original under a "shown in its original language" note — not a silent fallback that looks like a translation.

Because the source language is whatever the writer used, text is translated into *every* locale including English, so a question typed in Spanish reaches the supervisor in English and not just the reverse.

The default provider is offline and only covers seeded phrases. To translate arbitrary input, export either key before starting the server:

```bash
export DEEPSEEK_API_KEY=...   # or ANTHROPIC_API_KEY=...
```

`Shiftline.Translation.DeepSeek` and `Shiftline.Translation.Claude` sit behind the same behaviour and send the same prompt from `Shiftline.Translation.Prompt`, so the key you export is the whole of the switch and swapping providers cannot quietly change what the model was asked to do. DeepSeek defaults to the cheaper `deepseek-v4-flash`: this path runs once per locale per piece of text, so it is the cost that scales with usage. `TRANSLATION_MODEL` overrides the model.

## Architecture

### Why Phoenix

An earlier plan called for a client-only React + Vite prototype with in-memory fixtures. It pivoted, for three reasons:

1. **Real-time visibility is the product's core claim.** "Has the team seen this?" only demos convincingly when a response in one window moves the supervisor's board in another. LiveView plus PubSub gives that in a few lines; a client-only SPA can only fake it inside one tab.
2. **The workflow is a server-side state machine.** Guarded transitions, an audit trail and per-staff response records are naturally an Ecto schema plus a context, and the state survives a refresh instead of resetting.
3. **One language for domain and UI** keeps it small — no API layer, no client state library, no duplicated types.

The cost is needing Postgres locally instead of `npm run dev`, which is acceptable for an evaluated case study.

### Structure

```text
lib/
├── shiftline/
│   ├── coordination.ex            # context: the coverage state machine, and only that
│   ├── demo.ex                    # fixtures + the persona switcher standing in for auth
│   ├── coordination/
│   │   ├── tasks.ex               # the shift task board
│   │   ├── messages.ex            # department channels and direct messages
│   │   ├── events.ex              # the activity feed and the sentences in it
│   │   ├── notifier.ex            # the PubSub contract clients subscribe to
│   │   ├── staff_member.ex
│   │   ├── coverage_request.ex
│   │   ├── coverage_response.ex   # includes "pending" = viewed but not answered
│   │   ├── activity_event.ex
│   │   ├── message.ex             # addressed to a department or one person, never both
│   │   ├── message_read.ex        # who saw it, who acknowledged it
│   │   └── shift_task.ex
│   ├── translation.ex             # cache in front of a pluggable provider
│   └── translation/
│       ├── prompt.ex              # the instruction every provider shares
│       ├── local.ex               # offline default
│       ├── deepseek.ex
│       └── claude.ex
└── shiftline_web/
    └── live/
        ├── home_live.ex           # shell, URL state, event handlers, PubSub subscribe
        └── home_live/
            ├── ui.ex              # shared cards, icons, formatting helpers
            ├── today.ex
            ├── coverage.ex
            ├── messages.ex
            └── profile.ex
```

All writes go through `Shiftline.Coordination` or `Shiftline.Coordination.Tasks`, which validate the transition, record an activity event naming the real actor, and broadcast through `Shiftline.Coordination.Notifier`. The LiveView only renders state and dispatches actions.

`Shiftline.Demo` sits outside the domain on purpose. Everything a real deployment would delete — seeded fixtures, the reset button, and a persona switcher that hands out an identity with no proof of who is asking — lives there, so the line between what is real and what is scaffolding is visible in the module tree rather than in a comment. **Authentication replaces `Shiftline.Demo.personas/0` and nothing else:** every write function already takes an actor id and already checks department, role and ownership against it.

### Data model

- **`StaffMember`** — name, role, department, preferred language, supervisor flag.
- **`CoverageRequest`** — department, role, date, shift window, location, urgency, reason, handoff note, status, selected replacement, acknowledgement timestamp.
- **`CoverageResponse`** — one row per staff member per request (unique index), typed `pending | accepted | partial | declined`, with separate `viewed_at` and `acknowledged_at` so *seen*, *responded* and *acknowledged* stay three distinct facts. Partial offers carry a structured covered window validated against the shift.
- **`ActivityEvent`** — kind, actor, body: the incident's audit trail.
- **`ShiftTask`** — the department's work for the day, owned by one person at a time and claimable by anyone in the department.
- **`Message`** — a department channel post or a direct message, never both: a check constraint enforces that exactly one of `department` and `recipient_id` is set. `urgent` is open to anyone, `pinned` is supervisor-only.
- **`MessageRead`** — one row per person per message, with the same `viewed_at` / `acknowledged_at` split as `CoverageResponse`. Opening a conversation writes the first; only an urgent message asks for the second.

### The state machine

`open → contacting → claimed → approved → resolved`, enforced in the context, returning `{:ok, _}` or `{:error, reason}`:

- **`respond/4`** — only while active; an offer moves the request to `claimed`; partial offers require a valid window inside the shift.
- **`approve/3`** — requires an active request and an actual offer from the chosen person; records the approver.
- **`acknowledge_handoff/2`** — only from `approved`, and only by the approved replacement.
- **`ask_question/3`** — a question is a message, not a coverage answer. It records an event and marks the asker as having viewed, but never overwrites an existing offer, so asking "which desk?" after accepting cannot strand the request with nobody approvable.
- **`mark_viewed/2`** — opening the request as frontline staff feeds the supervisor's viewed count.

Every transition takes a `SELECT … FOR UPDATE` lock on the request row and re-checks its own preconditions *inside* the transaction, so two supervisors approving at once cannot both win and a double acknowledgement cannot produce duplicate follow-up requests.

### Profile and settings

Profile separates two kinds of fact, deliberately rather than as a scoping shortcut:

- **Operator-managed, read-only** — name, role, department, property. These are administratively controlled in a workforce product, and since `approve/3` gates on `is_supervisor`, a self-service form that could write them would be a privilege escalation. `StaffMember.settings_changeset/2` does not cast those fields at all, so a crafted submission cannot reach them. There is a test for exactly that.
- **Worker-controlled, editable** — preferred language and in-app alerts.

Editable language is what turns "localization is part of the workflow" from a claim into a demonstration: the same supervisor can be switched to French and the entire operational surface follows, while identity stays put.

Notification preferences are narrow on purpose. In-app alerts are the only channel this prototype actually has, so it is the only one stored and honoured — muting it empties the feed and hides the pip rather than merely hiding a dot. Push and SMS appear explicitly disabled with a "not available in this prototype" note, rather than as switches that would quietly do nothing.

Saving settings re-mounts the LiveView rather than patching it, because gettext strings that don't reference an assign compile into the *static* half of the diff and are never re-sent on a patch. The same applies across windows: a settings change broadcasts `{:settings_updated, staff_id}` and any other window showing that person re-mounts.

## Tests and checks

```bash
mix test
```

```bash
mix format --check-formatted && mix compile --warnings-as-errors && mix assets.build
```

97 tests cover the state machine including its illegal transitions, department and role eligibility, the concurrency guards, task ownership, translation caching and provider adapters, and the LiveView surface.

The suite makes no network calls, and does not depend on your shell to keep it that way. `config/runtime.exs` is evaluated in every environment, so an API key exported for the demo would otherwise replace the stub provider and send the suite onto the network from inside the Ecto sandbox; test opts out of provider selection entirely, and a test asserts that. The adapters' response parsing is covered against recorded payload shapes instead.

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs the same checks on every push against a clean checkout with a cold build and no keys in the shell — the environment you have, rather than the one I developed in. It runs the suite twice, the second time with deliberately invalid API keys exported, because "the tests don't touch the network" is a claim about configuration and configuration is worth testing. A second job runs `mix assets.setup && mix assets.build`, since `mix setup` is your first command and a green test suite says nothing about whether it works on a machine that has never downloaded the tailwind and esbuild binaries.

## Security notes

User-typed text is sent to a third-party model for translation, which makes this the one place in the app where attacker-influenced content reaches an LLM. What that does and does not buy an attacker:

**Structural protections.** Text is sent as the **user turn**, never concatenated into the system prompt, so instruction and data stay in separate roles. The result is inert — it is stored as a string and rendered, and never becomes code, a query, a tool call, or a permission decision. Rendering is HEEx with no `raw/1` anywhere in `lib/shiftline_web/`, so markup in a translation is escaped rather than executed. Input is capped at 2,000 characters and cached by content hash, which bounds both cost and repeat traffic.

**The residual risk is content spoofing, not compromise.** A crafted note could try to talk the provider into emitting something other than a translation. The attacker already controls the source text, so what injection actually buys is the ability to make one message *say different things to different audiences* — an English-reading supervisor sees an innocuous note while Spanish-reading staff see something else.

The mitigation is to make translations checkable rather than authoritative: any machine-translated text carries a **"Show original"** control that switches the view back to what the author actually wrote. The mode lives in the URL (`?original=1`), so it survives a refresh and can be shared. A filter guessing at malicious output would be weaker — this makes a discrepancy visible to anyone who looks, without having to out-guess a model.

**Data residency is the bigger production question.** Staff names, shift patterns and reasons for absence leave the deployment for a third-party API. For an EU operator that is a GDPR matter — lawful basis, processor agreement, transfer mechanism — and it bears on provider choice, since DeepSeek is under Chinese jurisdiction. The behaviour in `Shiftline.Translation` means a self-hosted or EU-resident model is a config change, and the shared `Shiftline.Translation.Prompt` means swapping providers cannot alter what is asked.

## Scope and known gaps

A focused conceptual prototype, not a hospitality-management platform. No payroll, time tracking, PMS integration, guest communication, or production notification delivery.

Worth naming directly:

- **No authentication.** The persona switcher is the one intentionally fake thing; the guards behind it are real.
- **Times are UTC-naive and same-day.** A 22:00–06:00 shift crossing midnight would fail the `end_time > start_time` validation. The real fix is UTC datetimes plus the property's time zone.
- **The Today shift window is illustrative.** There is no Shift entity — complete workforce scheduling is out of scope per the brief.
- **One global PubSub topic.** Every client re-runs its data load on any change. Right for one hotel; the first thing to scope per-department for a chain.

## Background

Research and design work that preceded the build, in `docs/`. These are design-stage records rather than descriptions of the shipped app — each carries a header saying so, and `ux-flow.md` notes where implementation deliberately diverged from the plan.

- [`challenge-brief.md`](docs/challenge-brief.md) — the assignment
- [`market-research.md`](docs/market-research.md) — the competitive landscape and where the opportunity sits
- [`ux-flow.md`](docs/ux-flow.md) — prototype scope and screen-by-screen flow
- [`visual-direction.md`](docs/visual-direction.md) — the visual system and its rationale

[`AI-USAGE.md`](AI-USAGE.md) documents how AI tooling was used to build this.
