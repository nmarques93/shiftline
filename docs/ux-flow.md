# First Prototype UX Flow

## Prototype Direction

Build one focused mobile-first experience for a mid-sized hotel team. The prototype should prove that a supervisor can turn an unexpected absence into a visible, two-way coverage decision, and that a frontline worker can understand and act on it without entering a chat maze.

The product is an operational communication hub, not a general-purpose social feed. Every important message should answer three questions:

- What needs my attention now?
- What action can I take?
- What changed after I acted?

## Prototype Scope

### In scope

- Role-aware Today home for a supervisor and a frontline staff member.
- Urgent update and coverage request with a persistent status.
- Localized message, task, notification, and response labels.
- Two-way responses: accept, decline, partial coverage, and ask a question.
- Supervisor acknowledgement tracking.
- Confirmed replacement and handoff details visible to the affected team.
- Small department conversation attached to the incident.

### Out of scope

- Full schedule editing, payroll, time tracking, or property-management integration.
- Authentication and employee provisioning beyond a lightweight profile.
- A complete inbox, social feed, or exhaustive department directory.
- Automated matching of employees to shifts.

## Personas And Prototype Data

Use two test accounts and one incident so the prototype can be followed end to end.

### Supervisor: Maya Chen

- Role: Front Office Supervisor
- Department: Front Office
- Preferred language: English
- Shift: 14:00-22:00, Lobby
- Goal: Cover an unexpected absence and know who has seen the update.

### Frontline staff: Luis Garcia

- Role: Front Desk Agent
- Department: Front Office
- Preferred language: Spanish
- Shift: 14:00-22:00, Lobby
- Goal: Quickly understand whether he can help, ask a question, and see the final handoff.

### Incident

- Absent employee: Jordan Lee, Front Desk Agent
- Date: Today, Friday 14 August
- Shift: 18:00-22:00
- Location: Lobby front desk
- Need: One qualified front desk agent
- Urgency: Starts in 2 hours

## Information Architecture

Use a four-item bottom navigation on mobile:

1. **Today**: attention, current shift, tasks, and relevant team activity.
2. **Messages**: department conversations and direct conversations, with urgent items pinned above the feed.
3. **Work**: coverage requests and assigned tasks, filtered to the current user by default.
4. **Profile**: role, department, language, and notifications.

The active urgent incident is visible in Today and Work. It is not duplicated as unrelated chat content. Opening it always returns to the same incident detail and status history.

## Primary UX Flow: Coverage Incident

The prototype should support this complete path:

`Supervisor Today -> Create coverage -> Review and send -> Luis Today -> Localized response -> Supervisor responses -> Confirm replacement -> Luis handoff`

### 1. Supervisor sees the operational starting point

**Screen: Supervisor Today, default state**

Purpose: Make the next action obvious without requiring the supervisor to scan messages.

Content:

- Header: `Good afternoon, Maya` and `Front Office`
- Urgent card: `No active incidents` in the baseline state.
- Current shift card: `14:00-22:00 | Lobby` with `3 tasks open`.
- Task card: `Inspect lobby desk handoff | Due 17:45`.
- Team activity: `Housekeeping completed the 15:00 room release update`.
- Primary action: `Create update`.

Key interactions:

- Tap `Create update` to open the update type chooser.
- Tap an existing urgent card to resume an incident.
- Tap a task to see owner, status, and attached replies.

State to show in the prototype: an urgent badge appears on the Today tab as soon as the coverage request is created. It includes a count, for example `1 urgent`.

### 2. Supervisor starts a coverage request

**Screen: Create update, type selection**

Purpose: Keep creation focused on operational intent.

Show three large choices:

- `Coverage needed` with a person/shift icon.
- `Task update` with a checklist icon.
- `Team announcement` with a notice icon.

Select `Coverage needed`. Do not expose scheduling tools or a free-form chat composer first.

### 3. Supervisor defines the incident

**Screen: Coverage request form**

Purpose: Capture only the details needed to act.

Fields and recommended defaults:

- Department: `Front Office` (pre-filled from Maya's profile)
- Role: `Front Desk Agent`
- Date: `Today, Fri 14 Aug`
- Time: `18:00-22:00`
- Location: `Lobby front desk`
- People needed: `1`
- Urgency: `Starts in 2 hours` (automatically calculated; editable only as `Urgent` or `Standard`)
- Note: `Jordan is unexpectedly unavailable. We need front desk coverage for the evening shift.`

Key interactions:

- Tap a field to use a constrained selector rather than free text.
- Tap `Add handoff note` to optionally add `Please review VIP arrivals with Maya at 17:45.`
- Tap `Preview request` only when the required fields are complete.

Validation state:

- Missing required fields show an inline message, for example `Select a time`.
- The primary action remains disabled until department, role, time, and location are present.

### 4. Supervisor reviews and sends

**Screen: Coverage request preview**

Purpose: Let Maya catch scope and wording errors before notifying staff.

Show the exact notification card:

> **Urgent coverage needed**
> Front Desk Agent | Today, 18:00-22:00
> Lobby front desk
> Jordan is unexpectedly unavailable. Can you cover all or part of this shift?

Show audience and language behavior:

- Audience: `Eligible Front Office team members`
- `12 people will be notified`
- `Each person receives this in their preferred language`
- Maya's preview language: `English`

Key interactions:

- `Edit` returns to the form.
- `Send urgent request` opens a confirmation sheet with `Notify 12 teammates`.
- Confirmation copy: `They can accept, decline, offer partial coverage, or ask a question.`

After send, show a toast or inline confirmation: `Request sent. Waiting for responses.` The request is now a persistent incident, not just a sent message.

### 5. Frontline staff receives urgent visibility

**Screen: Luis Today, urgent state**

Purpose: Surface the action above ordinary team updates, even if Luis opens the app mid-shift.

Top-of-screen urgent card:

- Red/amber urgency treatment paired with the text label `Urgent`.
- `Coverage needed`
- `Today, 18:00-22:00 | Lobby front desk`
- `Starts in 2 hours`
- `Jordan is unexpectedly unavailable.`
- Status: `Response needed`

The rest of Today remains useful but visually secondary:

- Current shift: `14:00-22:00 | Lobby`
- Assigned task: `Complete lobby handoff checklist | Not started`
- Team update: `Welcome Ana, our new night auditor`.

Key interactions:

- Tap the urgent card to open incident detail.
- A push notification deep-links to this card and uses the same localized content.
- If Luis has already responded, replace `Response needed` with his response state.

Do not rely on color alone for urgency. Use `Urgent`, clear time language, an icon, and persistent placement.

### 6. Frontline staff reads and responds in context

**Screen: Coverage incident detail, Luis in Spanish**

Purpose: Make comprehension and response possible in one screen, without a separate translation step or chat channel.

Localized sample content:

> **Se necesita cobertura urgente**
> Agente de recepción | Hoy, 18:00-22:00
> Recepción del vestíbulo
> Jordan no podrá asistir inesperadamente. ¿Puedes cubrir todo o parte de este turno?

Show:

- `Publicado por Maya Chen | Supervisora de recepción`
- A visible `Español` language control, with `Ver en English` as the alternate action.
- Handoff note: `Revisa las llegadas VIP con Maya a las 17:45.`
- Response state: `Aún no has respondido`.

Primary response actions should be large, thumb-friendly buttons:

- `Puedo cubrir todo`
- `Puedo cubrir parte`
- `No puedo cubrir`
- `Hacer una pregunta`

Choosing `Puedo cubrir todo` opens a lightweight confirmation: `Confirmar cobertura de 18:00 a 22:00?` with `Confirmar` and `Cancelar`.

Choosing `Puedo cubrir parte` opens two time selectors prefilled with the incident window and a note field. Sample: `Puedo cubrir de 18:00 a 20:00`.

Choosing `No puedo cubrir` submits immediately after an optional reason selector: `Ya estoy trabajando`, `No disponible`, or `Otro`.

Choosing `Hacer una pregunta` expands an in-context composer. Sample question: `¿Hay uniforme preparado para la recepción?` The question appears in the incident thread and not in a generic department feed.

After any response, show an explicit state such as `Tu respuesta fue enviada a Maya` and `Esperando confirmación`. The response button group becomes a compact `Cambiar respuesta` action.

### 7. Supervisor tracks responses

**Screen: Supervisor incident detail, responses pending**

Purpose: Give Maya operational confidence without opening multiple chats.

Header:

- `Coverage needed`
- `Today, 18:00-22:00 | Lobby front desk`
- Status chip: `Waiting for confirmation`

Response summary:

- `8 of 12 viewed`
- `3 responses`
- `1 full coverage offer`
- `1 partial coverage offer`
- `1 declined`

Response list rows should show name, response, and acknowledgement status:

- `Luis Garcia | Full shift | Viewed 16:04`
- `Priya Shah | Part: 18:00-20:00 | Viewed 16:06`
- `Omar Haddad | Declined | Viewed 16:05`
- `4 not viewed` with `Remind those not viewed`.

Key interactions:

- Tap a response to view the reply or question.
- Tap `Reply` to answer in the incident thread.
- Tap `Remind those not viewed` to send one non-duplicative reminder.
- Tap `Select replacement` only after reviewing the offers.

Question example and answer:

- Luis: `Is a uniform prepared for the front desk?`
- Maya: `Yes. It is in the supervisor locker, labeled "Front Desk PM".`

### 8. Supervisor confirms the replacement

**Screen: Confirm replacement sheet**

Purpose: Make ownership explicit and close the open loop.

Show the selected offer:

- `Luis Garcia`
- `Full shift | 18:00-22:00`
- `Front Desk Agent | Lobby front desk`

Required confirmation fields:

- Replacement: `Luis Garcia`
- Handoff owner: `Maya Chen`
- Handoff detail: `Meet Maya at the lobby desk at 17:45. Review VIP arrivals and the cash drawer count.`

Primary action: `Confirm Luis as replacement`.

Confirmation copy should state the consequence: `This closes the coverage request and updates the Front Office team.`

### 9. Team sees the resolved handoff

**Screen: Incident detail, confirmed state**

Purpose: Show exactly what changed, to both roles.

Persistent status:

- `Covered`
- `Luis Garcia confirmed | Today, 18:00-22:00`
- `Handoff at 17:45 with Maya Chen`

Timeline:

- `15:42 Maya created urgent coverage request`
- `16:04 Luis offered full coverage`
- `16:08 Maya confirmed Luis`
- `Now Front Office team notified`

Supervisor view adds:

- `12 notified`
- `10 acknowledged`
- `2 not yet viewed`
- `Send reminder`.

Luis view adds:

- `Your shift has been added to Today`
- `View handoff checklist`.

The response controls are replaced by a read-only confirmation summary. A `Report a problem` action remains available so the two-way channel does not disappear after assignment.

### 10. Frontline staff sees the resulting assignment

**Screen: Luis Today, resolved state**

Move the incident from the urgent response slot to an assigned-work slot while retaining a small `Covered` history marker.

Content:

- `Evening coverage confirmed`
- `You are covering Front Desk Agent | 18:00-22:00`
- `Lobby front desk`
- `Handoff: 17:45 with Maya at the lobby desk`
- Action: `Open handoff checklist`

This is the key outcome: a request has become an owned assignment with a clear next step.

## Screen Inventory

The first prototype needs 10 primary screens and 3 lightweight overlays. All screens are mobile-sized; the supervisor view can be shown in the same frame with role-specific content.

| ID | Screen | User | Purpose | Required states |
| --- | --- | --- | --- | --- |
| S1 | Today | Supervisor | See shift, tasks, team activity, and create an update | Baseline; one urgent incident |
| S2 | Today | Frontline staff | See what needs attention and current responsibilities | Unread urgent; response pending; assignment confirmed |
| S3 | Update type chooser | Supervisor | Start a coverage, task, or announcement flow | Default; coverage selected |
| S4 | Coverage request form | Supervisor | Define department, role, time, location, urgency, and note | Empty/default; validation error; complete |
| S5 | Coverage request preview | Supervisor | Review audience, language behavior, and exact message | Ready to send; send confirmation |
| S6 | Incident detail | Frontline staff | Read localized request and respond in context | Needs response; responding; response sent |
| S7 | Incident detail | Supervisor | Monitor views, responses, questions, and reminders | Waiting; responses received; no response |
| S8 | Confirm replacement sheet | Supervisor | Select an offer and define handoff ownership | Offer selected; confirm action |
| S9 | Incident detail | Both roles | Display resolved status, timeline, and acknowledgement | Covered; acknowledgement incomplete |
| S10 | Work / handoff detail | Frontline staff | Show the resulting assignment and handoff checklist | Assigned; handoff complete |
| O1 | Response confirmation | Frontline staff | Confirm full coverage or prevent accidental submission | Full coverage; cancel |
| O2 | Partial coverage editor | Frontline staff | Capture available time and optional note | Valid range; invalid range |
| O3 | Language selector | Any user | Change preferred display language in context | English; Spanish; apply confirmation |

### Deliberately not separate screens

- Read receipts and acknowledgement counts are sections of incident detail, not a separate analytics view.
- Questions and replies stay in the incident thread, not a new chat screen.
- Notifications deep-link into Today or the incident detail rather than adding a notification center.
- Profile can be a simple fourth-tab screen with editable language and notification settings; it does not need to be part of the coverage demo path.

## Key States And Interaction Rules

### Urgency

- `Urgent` is a text label and persistent card treatment, not color alone.
- An urgent request remains in Today until the user responds or the supervisor closes it.
- When resolved, it changes to `Covered` rather than disappearing.
- The request shows relative and absolute time: `Starts in 2 hours` and `Today, 18:00-22:00`.

### Acknowledgement

Use three explicit states:

- `Not viewed`: delivered but not opened.
- `Viewed`: opened, but no action taken.
- `Acknowledged`: user accepted, declined, or submitted a partial offer.

For the prototype, `Viewed` is enough to demonstrate visibility. Do not imply that opening a message means accepting responsibility.

### Localization

- Seed Luis with Spanish and Maya with English.
- Translate the request, response actions, task labels, push notification, and confirmation status.
- Preserve names, times, and operational terms consistently.
- Include `Ver en English` on the incident detail so a staff member can recover if a translation is unclear.
- Let users change language from Profile and from the incident's language control; the change should update the current screen immediately.

### Two-way communication

- Every incident has a reply affordance after the initial request.
- Questions are visible to the supervisor in the response summary and have a clear reply state.
- A staff member can change a response before confirmation; after confirmation, use `Report a problem` rather than silently editing the assignment.
- Avoid a generic `Like` or emoji-only acknowledgement for an operational request.

### Loading, empty, and error states

- Loading: retain the Today shell and show skeletons only inside cards; never hide the urgent tab badge.
- Empty Today: `You are all caught up` followed by the current shift card.
- No coverage responses: `No responses yet` plus `Remind those not viewed` after at least one person has viewed the request.
- Send error: preserve the completed form and show `Could not send. Try again` with a retry action.
- Offline response: show `Response not sent` and keep the response draft; do not display a false acknowledgement.

## Prototype Success Checks

Use these as clickable-prototype acceptance criteria:

- A supervisor can create and send a coverage request in under one minute.
- A frontline worker can identify the urgent request from Today without opening Messages.
- Luis can understand the request and submit a full, partial, declined, or question response in Spanish.
- Maya can distinguish not viewed, viewed, and acknowledged recipients.
- Maya can answer Luis's question and confirm one replacement.
- Both roles can see the final owner, time, location, and handoff after confirmation.
- No key step requires a separate WhatsApp-style conversation or an external scheduling system.
