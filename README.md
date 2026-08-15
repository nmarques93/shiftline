# Sona

Sona is a Phoenix LiveView prototype for hospitality team communication. It explores how hotel teams can replace fragmented WhatsApp coordination with a visible, localized, two-way workspace.

The prototype focuses on one operational scenario: finding coverage when a front desk employee is unexpectedly unavailable.

## Stack

- Elixir 1.17 or newer (developed on 1.19)
- Phoenix 1.8
- Phoenix LiveView
- Ecto with PostgreSQL
- Tailwind CSS
- Bandit HTTP server

## Requirements

- Elixir 1.17+ and Erlang/OTP
- PostgreSQL
- Node is not required for the application runtime

The development configuration expects PostgreSQL at `localhost:5432` with:

```text
username: postgres
password: postgres
database: sona_dev
```

## Setup

Install dependencies, create the database, run migrations, seed the demo data, and build assets:

```bash
mix setup
```

Start the development server:

```bash
mix phx.server
```

Open [`http://localhost:4000`](http://localhost:4000).

## Demo Flow

The interface includes two switchable perspectives:

- **Maya Chen:** Front Office Supervisor
- **Luis Garcia:** Front Desk Agent, Spanish preference

The main workflow is:

1. As the supervisor, open **Coverage → New coverage request** and report an absence. The app ships with one seeded incident so there is something to look at on load, but requests are created here, not fixtures.
2. Switch to the frontline perspective and view the request — it appears in that person's own language.
3. Respond with full or partial coverage, decline, or ask a question.
4. Switch back to the supervisor perspective, review who has seen and answered, and approve a replacement.
5. Switch to the approved replacement and acknowledge the handoff.
6. For partial coverage, the shift is never shown as fully covered: follow-up requests are opened automatically for any remaining gaps.

Use **Reset demo** to restore the initial data state.

### See it update live

The current tab, perspective and focused incident are URL state, so the workflow can be watched from both sides at once. Open a second browser window at:

```text
http://localhost:4000/?view=coverage&role=frontline
```

Keep the supervisor view in the first window. A response submitted in one appears in the other immediately, without a refresh — the read/response counts are pushed over PubSub rather than polled.

### Multilingual behaviour

Language follows each person's own preference, set in **Profile**, and applies to the workflow itself rather than only to a settings screen. English, Spanish and French ship as catalogs.

Text that people type — a request reason, a note, a question — is translated by a pluggable service (`Sona.Translation`). The default provider is offline and only covers seeded phrases, so newly typed text appears under a "shown in its original language" note.

To translate arbitrary input, export either key before starting the server:

```bash
export DEEPSEEK_API_KEY=...   # or ANTHROPIC_API_KEY=...
```

Both adapters send the same prompt and satisfy the same behaviour, so the key you export is the whole of the switch. `TRANSLATION_MODEL` overrides the default model if you want a different one.

## Verification

Run the test suite and compile checks with:

```bash
mix format --check-formatted
mix test
mix compile --warnings-as-errors
mix assets.build
```

## Scope

This is a focused conceptual prototype, not a complete hospitality-management platform. It does not include authentication, payroll, time tracking, PMS integrations, guest communication, or production notification delivery.

Product research and design decisions are documented in:

- [`challenge-brief.md`](challenge-brief.md)
- [`market-research.md`](market-research.md)
- [`ux-flow.md`](ux-flow.md)
- [`visual-direction.md`](visual-direction.md)
- [`implementation-plan.md`](implementation-plan.md)
