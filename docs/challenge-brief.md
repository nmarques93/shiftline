# Hospitality Team Communication Challenge

## Challenge Focus

Design a hospitality-focused internal communication tool that replaces WhatsApp for daily team communication while improving operational visibility, coordination, and team belonging.

This is a conceptual technology challenge. The product should demonstrate a credible experience using informed assumptions rather than attempting to model a complete commercial hospitality platform.

## Primary Requirement

Enable hotel teams to replace fragmented WhatsApp communication with a visible, localized, two-way internal communication space for daily operations.

## Supporting Outcome

Help employees feel connected to the wider team and hotel, rather than isolated within their individual shifts or departments.

## Assumptions

- The setting is a mid-sized hotel with multiple departments.
- The main users are hotel supervisors and frontline staff.
- Staff may be multilingual, mobile-first, and time-constrained.
- Current communication is fragmented across WhatsApp groups, phone calls, paper notes, and hallway conversations.
- Supervisors need to broadcast information, coordinate changes, and confirm that messages were seen.
- Frontline staff need a simple way to respond, ask questions, request help, and understand what is expected of them.
- The product is used primarily on mobile devices, with a desktop or tablet view for supervisors.

## Core User Jobs

### Supervisor

- Share an important update with the right team or department.
- Find coverage when someone is unexpectedly unavailable.
- Assign work and know who owns it.
- See whether critical information has been received and acknowledged.
- Keep communication attached to the relevant shift, task, or incident.

### Frontline Staff Member

- Quickly see what matters for the current shift.
- Understand messages and tasks in their preferred language.
- Accept, decline, or clarify an assignment.
- Ask for help without needing a separate channel.
- Feel informed about the wider team and hotel.

## Primary Scenario

An employee is unexpectedly unavailable for a shift.

1. A supervisor creates a coverage update.
2. The update identifies the affected department, role, time, location, and urgency.
3. Eligible team members receive a prominent localized request.
4. Team members can accept, decline, offer partial coverage, or ask a question.
5. The supervisor confirms the replacement.
6. The affected team sees the updated assignment and handoff details.
7. The supervisor can see who viewed or acknowledged the update.

This scenario demonstrates the core product value without requiring a complete scheduling or payroll system.

## MVP Surface

### Today

A role-aware home view showing:

- Urgent updates
- Current shift information
- Assigned tasks
- Pending responses
- Team activity relevant to the user

### Messages

- Department and team conversations
- 1-to-1 conversations
- Pinned or urgent announcements
- Replies attached to the original context
- Read and acknowledgement status for critical updates

### Coverage and Tasks

- Create a coverage request
- Respond to a request
- Assign a task
- Change task status
- Confirm ownership and handoff

### Profile

- Name and role
- Department
- Preferred language
- Notification preferences

## Design Principles

### Visibility Over Volume

The experience should not reproduce an infinite chat feed. Critical information should be prioritized, persistent, and difficult to miss.

### Communication Must Lead to Action

Messages should support a clear next step such as acknowledge, accept, decline, assign, or complete.

### Low Friction for Frontline Workers

Use plain language, large touch targets, clear status labels, and minimal setup. Avoid requiring a corporate email address or lengthy onboarding.

### Localization Is Part of the Workflow

Language preference should affect messages, tasks, notifications, and responses, not just the settings screen.

### Two-Way by Default

Staff should be able to respond, ask questions, report blockers, and request help. The product should not feel like a manager-only announcement board.

### Belonging Through Context

Team identity should come from useful visibility into shared goals, updates, handoffs, and contributions rather than a separate social network layer.

## Out of Scope

- Full property-management system functionality
- Payroll and time tracking
- Complete workforce scheduling
- Automated labor-law compliance
- Guest-facing communication
- Real production integrations
- Public social features

## Success Criteria For the Prototype

The prototype should make it easy to answer these questions:

- What needs my attention right now?
- Which messages are urgent?
- What am I responsible for?
- How do I respond or ask for help?
- Has the team received the update?
- What changed after the coverage request was resolved?

## Suggested Product Statement

> A clear, multilingual communication hub for hotel teams that turns urgent updates into coordinated action.
