# Functional reference review — 2026-10-15

Source: https://ticktick.com/features, consulted 2026-10-15. Public feature descriptions are a usability reference, not an implementation or visual specification. No proprietary assets or source were imported. Visual differentiation alone is not a legal clearance claim.

| MindFlow area | Existing behavior | Remaining completion work |
| --- | --- | --- |
| Tasks | Local CRUD, lists, notes, priority, date, Inbox and smart views; priority filter, sorting and bulk complete/reopen/delete | Dedicated relationship schema, tags, subtasks, timed deadlines, reminders, recurrence and bulk move/scheduling |
| Matrix | Canonical urgent/important flags, drag/drop, shared editor | Keyboard quadrant movement and broader accessibility verification |
| Calendar | Date navigation and canonical dated tasks | Day/week/month grids, dated quick-add and recurring occurrences |
| Habits | UTC daily check-ins and persisted count | IANA timezone/local days, schedules, targets, streaks and history |
| Focus | Configurable sessions, pause/resume/finish and persisted history | Saved preferences, cycles/skip, task links and daily totals |
| Search | Reactive offline FTS with fallback and result navigation | Entity/status/list filters and performance verification |
| Foundation | Local SQLite/outbox, authenticated conflict-aware sync | Dedicated domain constraints, recovery matrix, device lifecycle and complete localization |

Implement in small vertical slices in the repository's delivery order. Recurrence needs stable occurrence records and timezone tests before calendar expansion. Habit enhancements need documented local-day semantics. No integrations, collaboration or other out-of-scope TickTick features are added. Keep MindFlow's warm backgrounds, teal palette, original wording, Material controls and responsive layout; avoid using TickTick screenshots as layout targets.
