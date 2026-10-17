# Tasks

Local transactional CRUD, lists, completion, notes, date and urgency/importance. Tags, subtasks, recurrence and reminders follow after tested sync.

## Task organization refinement — 2026-10-15

Inbox projects active canonical tasks with no list. All/Today (including overdue)/Upcoming/Completed views intersect the selected list and optional exact priority. Sort by priority, due date (undated last), title or newest creation; record identity breaks ties deterministically. Query logic lives in the task domain, independent of widgets.

Selection mode supports selecting visible results, completing/reopening and confirmed tombstone deletion. Actions affect only selected tasks in the current filtered results. Each bulk action reads current SQLite payloads and saves domain/outbox updates in one transaction, preserving newer notes and existing pending operations. Missing/deleted tasks are skipped. Selection and query controls are session UI state.

Functional reference: https://ticktick.com/features (consulted 2026-10-15) for lists, filters, priorities and productivity workflows. Implementation is independent; no source code, screenshots, icons, text or other assets were imported. MindFlow retains its teal Material 3 identity and wrapped task toolbar. Recurrence, reminders, tags and subtasks remain pending; this increment does not complete the full MVP.

## Shared task entry controls — 2026-10-17

The task workspace accepts a title directly; Enter or the return button commits a canonical task and outbox entry through the existing repository. Date and flag priority can be set before submission. Failed writes retain the draft, and submission is guarded while saving. The expand action opens the full editor. The shared date selector provides a calendar, Today/Tomorrow/Next week, explicit OK/Cancel and Clear; priority offers High/Medium/Low/None with colored flags. These same controls are used in the full editor and selected-task details. Date selection is staged until OK. Existing notes, list and matrix controls remain in the full editor.

This increment supports date-only scheduling. Time, duration, notification reminders and recurrence from the interaction references remain unimplemented; no inert controls are presented for them. No schema or sync protocol changes are introduced.

## Timed scheduling and direct details editing — 2026-10-17

Quick entry and the full editor share a date/time picker. Choosing a time creates optional `due_at` as a UTC ISO instant; the selected calendar date remains in `due_date`. OK commits staged values; Cancel discards them; Clear removes both, while Clear time preserves the date. Timed tasks display in the device timezone, including their date in task/calendar projections. Date-only tasks remain floating calendar dates. This schedules a due time; it does not schedule a notification.

Selecting a task opens editable details immediately (side pane on wide task workspaces, dialog on compact layouts). Title, notes, completion, date/time, priority, list and matrix attributes save locally without an Edit or Save button. Writes serialize per editor and merge only changed fields against the current SQLite row transactionally, preserving other edits and outbox atomicity. Invalid blank titles are shown but never persisted. Save errors retain draft text and expose Retry. No new dependencies or database table migrations are needed for the JSON-envelope field.
