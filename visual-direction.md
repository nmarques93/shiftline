# Visual Direction: Sona

## Direction: The Operations Signal

Sona should feel like the calm, well-marked service corridor behind a hotel: immediate when something needs action, legible at a glance, and full of useful evidence after the handoff. It is not a social feed and it should not look like a corporate chat tool.

The visual system is built around three ideas:

- **Signal:** what needs attention now is visually distinct from routine activity.
- **Shift:** time, department, location, and ownership are always close to the communication.
- **Handoff:** every important update leaves a visible trail from request to response to resolution.

The emotional target is composed urgency: operationally serious without feeling alarmist, warm enough to reinforce that a hotel is a team of people, not a set of tickets.

## Brand Character

- Grounded, observant, and human.
- Warm in moments of team recognition; restrained during operational pressure.
- Plainspoken rather than polished or promotional.
- Hotel-native without using keys, beds, buildings, luggage, or generic hospitality stock imagery as decoration.
- Dense with relevant context, never dense for its own sake.

Avoid:

- Infinite chat feeds as the primary home experience.
- Purple-blue SaaS gradients, glass panels, floating blobs, or abstract sparkle.
- Excessive rounded cards that make every item look equally important.
- Red as a default synonym for unread or urgent.
- A separate "social" area that distracts from useful team belonging.

## Typography

Use a two-family system with a clear functional split:

- **Display and navigation:** `DM Sans`, 600-700. Friendly, compact, and highly legible on small screens. Use for page titles, section labels, button labels, and numeric status values.
- **Operational reading:** `Atkinson Hyperlegible`, 400-700. Use for message content, task details, translated text, and longer explanatory copy. Its open forms help under time pressure and support varied reading ability.

Fallback stacks:

- `DM Sans, Arial, sans-serif`
- `Atkinson Hyperlegible, Arial, sans-serif`

Type scale:

| Token | Size / line height | Use |
| --- | --- | --- |
| `display` | 32 / 36 px | Desktop page title only |
| `title` | 24 / 29 px | Mobile page title, incident title |
| `section` | 18 / 23 px | Section headings |
| `body` | 16 / 23 px | Messages, task descriptions, primary reading |
| `label` | 13 / 16 px | Metadata, filters, status labels |
| `micro` | 11 / 14 px | Timestamps and read receipts only |

Do not use micro type for information someone must act on. Never communicate urgency by reducing type size or relying on all caps. Sentence case is the default; use uppercase only for short status labels where the label is also paired with color and an icon.

## Color Palette

The palette should recall early morning service light, deep green tile, and a visible amber indicator, not a luxury hotel brochure.

### Core tokens

| Token | Hex | Role |
| --- | --- | --- |
| `ink-950` | `#172421` | Primary text, dark controls |
| `ink-700` | `#445651` | Secondary text, metadata |
| `paper` | `#F7F4EC` | App canvas, warm neutral base |
| `surface` | `#FFFDF8` | Cards, sheets, message surfaces |
| `line` | `#D9DED5` | Dividers, input borders |
| `moss-700` | `#24594D` | Brand anchor, selected navigation, links |
| `moss-100` | `#DDEBE2` | Soft selected state, translated text background |
| `amber-500` | `#D98528` | Attention, pending response, active coverage |
| `amber-100` | `#FBE7C7` | Attention surface |
| `coral-600` | `#C65343` | Critical disruption, destructive action |
| `coral-100` | `#F7DCD5` | Critical surface |
| `blue-700` | `#28638A` | Informational status, links when moss is already in use |
| `blue-100` | `#DCEBF2` | Informational surface |
| `success-700` | `#31734E` | Confirmed, complete, acknowledged |
| `success-100` | `#DCECDC` | Confirmed surface |

Use `paper` as the persistent environment and `surface` for content that sits above it. This creates a quiet sense of place without shadows doing all the separation. Keep shadows minimal: `0 2px 8px rgb(23 36 33 / 8%)` for an open sheet or elevated action only.

Color rules:

- `moss-700` is the default action and trust color, not a decorative accent.
- `amber-500` means "needs a response" or "in progress", never merely "unread".
- `coral-600` is reserved for an active operational risk or destructive confirmation.
- Pair every semantic color with text, an icon, or a shape. Never use color alone for status.
- On `paper` and pale surfaces, use `ink-950` or the 700 semantic token for text. Do not use amber or coral as body text.

## Layout Principles

### 1. Start with the shift, not the inbox

The Today view leads with a compact shift strip: role, department, local time window, and location. Below it, show the next required action, then urgent updates, assigned work, and team activity. The order answers the frontline questions in the brief: what matters, what is mine, and what changed.

### 2. One operational spine

Every coverage request, task, or urgent announcement has a consistent header: status, owner, department, time, and location. Replies, translated copy, and acknowledgement history stay attached to that object. Do not split the workflow between a chat thread and a separate task record.

### 3. Use weight and position to express priority

Critical items occupy the first position and use a stronger left rail, not a larger collection of visual effects. Routine updates can be compact rows. Resolved items recede into the activity trail but remain findable.

### 4. Give the page a service-zone rhythm

Use broad section bands named for the work: `On your shift`, `Needs a response`, `Your tasks`, `Team handoffs`. This is more useful than generic `Overview`, `Activity`, and `Updates`. Sections have 24 px vertical separation; content inside sections uses 12-16 px gaps.

### 5. Keep context beside action

Actions sit on the same surface as the request they affect. A coverage card should expose `Accept`, `Decline`, `Offer partial`, and `Ask a question` without opening a different composer. A task should expose ownership and completion where the task is read.

### 6. Let breathing room signal safety

Use a 4 px spacing base: 4, 8, 12, 16, 24, 32, 40. Use 16 px page padding on mobile and 32-48 px on desktop. Avoid edge-to-edge walls of cards; a single strong object is easier to act on than a grid of equal panels.

## Navigation and Page Structure

### Mobile frontline view

Use a four-item bottom navigation: `Today`, `Messages`, `Tasks`, `Profile`. `Coverage` is not a fifth destination; active coverage requests appear in Today and Messages, and supervisors can create them from a persistent action button or the relevant shift context.

The Today header includes:

- Hotel or property name and current local date.
- Shift pill with department, role, and time.
- A small language control that labels the active language by name, not a flag.

The primary scroll is a prioritized stack, not a masonry grid. Keep the next action within the first viewport whenever possible. A sticky action bar may hold the one most important response for an open incident.

### Desktop supervisor view

Use a two-column workspace rather than a conventional admin dashboard:

- Left rail, 232 px: property mark, current property and department switcher, `Today`, `Messages`, `Coverage`, `Tasks`, and `Profile`.
- Main work area, max 1120 px: prioritized operational feed and open incident detail.
- Optional right detail rail, 320 px: acknowledgement or handoff trail when an incident is selected.

The desktop view may show more simultaneous context, but it must retain the same hierarchy and component language as mobile. Do not introduce a separate visual system for supervisors.

## Component Treatment

### Shift strip

A low, horizontal band with a moss leading edge and a simple clock or shift icon. Show `Housekeeping`, `07:00-15:00`, and `Floor 3` as separate readable fields. It is a contextual anchor, not a decorative hero banner.

### Signal card

The primary object for urgent work. Use a warm pale surface, 4 px coral or amber left rail, a clear status label, concise title, and structured facts in a two-column list. Put the response controls in a full-width action row. Include `Updated 8 min ago` and a visible response count when relevant.

### Coverage card

Show the request as a case, not a chat message:

`OPEN` -> `CONTACTING` -> `CLAIMED` -> `APPROVED` -> `RESOLVED`

Represent this progression as a short labelled step trail with the current step filled. The card includes affected shift, location, required skill, urgency, and the person who owns resolution. Once resolved, show the replacement and handoff note prominently before collapsing the response history.

### Message thread

Use a transcript with generous 16 px message text and a context header pinned above it. Avoid alternating colorful bubbles. Messages use a quiet surface with a thin line; the active reply has a moss marker. A translated message displays the localized version first, followed by a small `View original` disclosure.

### Task row

Use a checkbox or completion control at the left, task name and location in the center, and owner/status on the right. Do not turn every task into a card. A task row can expand to reveal handoff notes and a compact reply thread.

### Acknowledgement trail

Use people-first rows with avatar initials or a supplied photo, name, role, response state, and time. States are explicit: `Viewed`, `Acknowledged`, `Declined`, `Waiting`. Avoid tiny checkmark-only receipts. Supervisors should see the unresolved gap first, followed by completed acknowledgement.

### Team activity

Keep belonging operational: `Lina handed over Room 312 to Marco`, `Engineering cleared the ice machine issue`, or `Front desk welcomed two new starters`. Use names, department colors only as small markers, and the useful outcome. No likes, follower counts, or vanity metrics.

### Controls

- Primary button: moss fill, white text, 12 px radius, 48 px minimum height.
- Secondary button: transparent or surface fill with ink text and a line border.
- Destructive button: coral only where the action truly discards or escalates.
- Segmented choices: use a pale surface and a 2 px moss selected outline, with labels always visible.
- Inputs: warm surface, 1 px line border, 12 px radius, clear label above, inline error below.
- Icon buttons: 44 x 44 px minimum, tooltip or accessible label, never the only way to understand status.

Use 12 px corner radii for interactive cards and controls. Reserve a sharper 4 px radius for status markers and step indicators so the operational layer feels more like signage than a toy interface.

## Mobile and Desktop Behavior

Mobile is the source of truth because frontline staff may be moving through back-of-house areas with one hand and limited attention.

- Keep touch targets at least 44 x 44 px; use 48 px for primary responses.
- Stack coverage facts vertically below 360 px wide; use a two-column fact grid above that.
- Keep the response bar sticky only while a request is open; do not hide content behind it.
- Use bottom sheets for language selection, acknowledgement details, and filters. The sheet title and close action must remain visible.
- Support long names, translated strings, and large text without clipped buttons. Buttons can wrap to two lines.
- Preserve the original message behind a disclosure rather than forcing a side-by-side translation on a narrow screen.
- Use pull-to-refresh only as a supplement; show the last updated time and a visible refresh action for confidence in urgent states.

Desktop expands relationships, not decoration:

- Keep the main feed readable at roughly 640-760 px line length.
- Put acknowledgement and handoff evidence in a detail rail or drawer, not in tiny table columns.
- Allow supervisors to filter by department, status, shift, and location without removing the primary urgency order.
- On tablet widths, collapse the left rail to icons with labels available on focus and move the detail rail below the selected case.

## Accessibility and Localization

- Meet WCAG 2.2 AA contrast at minimum: 4.5:1 for normal text, 3:1 for large text and meaningful UI boundaries.
- Do not rely on red/green or icon shape alone. Every state has a text label and, when useful, a short explanation.
- Use semantic headings, landmarks, native buttons, and labelled form controls. Reading order must follow the operational priority.
- Announce new urgent requests and status changes to assistive technology without stealing focus from an active task. Provide a way to review alerts later.
- Support keyboard navigation on desktop, visible focus rings using a 2 px `moss-700` outline plus 2 px offset, and a skip link to the main work area.
- Respect reduced motion. Status changes should use a brief color or border change rather than bouncing, pulsing, or auto-advancing motion.
- Never use flags to represent language. Use language names in their own native form where practical, such as `English`, `Espanol`, or `Francais`.
- Keep translation status visible: show the preferred-language message, the translation timestamp, and a `View original` control. Preserve names, times, room numbers, and locations exactly.
- Avoid idioms in source copy. Use short verbs such as `Acknowledge`, `Accept coverage`, `Ask a question`, and `Mark complete`.
- Allow text resizing to 200% and increased line spacing without loss of action controls. Test German, Spanish, French, Arabic, and long department names.
- Provide a non-color distinction for urgency: left rail, status text, alert icon, and placement in the priority stack.

## Prototype Content Rules

Use believable hotel language and concrete context in the prototype:

- `Housekeeping / Floor 3 / 07:00-15:00`
- `Coverage needed: Room attendant, 14:00-22:00, North wing`
- `Reply by 12:30`
- `Marco accepted partial coverage: 14:00-18:00`
- `Handoff: master key returned to Front Desk`

Show at least one unresolved request, one clear response, one translated message, and one resolved handoff in the main flow. This makes the visual direction demonstrate the closed loop rather than merely styling a chat list.

## Implementation Notes

- Define color, type, spacing, radius, and elevation as tokens before building components.
- Build `ShiftStrip`, `SignalCard`, `CoverageCard`, `TaskRow`, `MessageThread`, and `AcknowledgementTrail` as reusable primitives with status variants.
- Keep status values data-driven so the same case can render consistently in Today, Messages, and Coverage.
- Use CSS logical properties and flexible layouts for right-to-left languages.
- Test at 320 px, 375 px, 768 px, 1024 px, and 1440 px widths, plus a large-text browser setting.
- Prototype the unresolved-to-resolved coverage path first. It is the clearest proof that Sona turns communication into coordinated action.
