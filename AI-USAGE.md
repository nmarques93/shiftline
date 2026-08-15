# How AI was used on this case study

I used AI assistance throughout this exercise and want to be straightforward
about where and how, so the code can be read with an accurate picture of how
it was produced.

**Tool:** Claude Code (Claude Opus 5), driven interactively from the terminal.

---

## The division of work

**What I directed.** The product direction and every scope decision were mine:
choosing to build one deep vertical slice of the coverage workflow rather than
four shallow screens; pivoting the stack from the React plan I had originally
written to Phoenix LiveView once real-time read receipts became the central
claim; deciding that Profile settings should be editable but that role and
department must not be; deciding that partial coverage had to be modelled
honestly rather than displayed as full coverage; and requiring that translation
work on arbitrary user input rather than only on seeded strings.

**What I caught.** Several defects in this codebase were found by me reading and
using the running app, then handed back as work to do:

- approving a *partial* coverage offer was being presented as if the whole
  shift were covered;
- switching between staff members with different languages left parts of the
  page in the previous language until a manual refresh;
- the notifications button did nothing, and its icon did not fit its button.

I also ran independent code review passes against the tree and fed the findings
back in. Those rounds surfaced the concurrency and data-integrity issues —
races between simultaneous approvals, non-atomic acknowledgement, a question
overwriting a coverage offer — that shaped much of the final domain design.

**What the AI did.** Implementation, refactoring, test writing, and running the
app in a browser to verify behaviour end to end. It also proposed several
designs I accepted after discussion — the follow-up-request mechanism for
uncovered gaps, the row-locking approach to the transitions, and the write-time
translation cache. Where I disagreed or wanted a different scope, I said so and
it changed course.

## Verification

I did not accept generated code on trust. Everything here was checked by:

- an automated test suite covering the workflow's state machine, including its
  illegal transitions and failure paths (`mix test`);
- driving the running application in a browser for each change — creating
  requests, responding, approving, acknowledging, switching languages, and
  checking two windows update live;
- independent review passes over the tree, with the findings fixed and
  re-verified.

Where something is unfinished or deliberately out of scope, it is written down
rather than hidden — see the "known gaps" discussion in `implementation-plan.md`.

## What I would say about it in conversation

I am comfortable explaining any decision in this repository: why the workflow is
a guarded state machine in the context rather than booleans in the UI, why
transitions take a row lock, why questions are activity events rather than
responses, why translation happens on write, and why identity fields are not
self-editable. If a reviewer wants to probe any file, I can walk through the
reasoning rather than the syntax.

## Commit history

The repository was initialised at the end of the exercise, so the commits are a
logical decomposition of the finished tree rather than a live record of the
order the work happened in. Timestamps have not been altered to suggest
otherwise. Commits carry a `Co-Authored-By` trailer for the AI assistance, for
the same reason as this file.
