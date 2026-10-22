# UI design

MindFlow uses an original quiet teal identity: seed #24786B, warm light background #F6F7F3, generous rounded cards, spacious page headings, restrained tonal emphasis and Material 3 controls. Dark colors derive from the same seed. Spacing scale: 4, 8, 12, 16, 24, 32. Non-task content has a max width of 1200. Task columns adapt to available space; navigation placement follows the platform, with a persistent desktop icon rail and six bottom destinations on mobile.

Tasks are the launch view. All views share the task editor and canonical records. Quick add sits above the task list and remains available from other views in the shell; Ctrl/Cmd+N creates a task, Ctrl/Cmd+K opens search. Theme/language controls and sync attention are visible. Form validation, destructive confirmations, loading/error states and semantic Material controls are mandatory. EN/VI labels are incrementally implemented; untranslated strings are tracked in status.

Task organization uses a vertical list of views and projects, a compact sorting/priority toolbar, a result count and an explicit selection mode. Controls wrap on compact viewports; new labels support English and Vietnamese. Bulk actions appear only in selection mode. TickTick's public feature descriptions inform functional requirements only; MindFlow's visual system and implementation remain independent.

## Task workspace and adaptive navigation

Desktop platforms retain a 64 px icon rail at every window width, with the account menu at the bottom. Android/iOS (including their web platform classification) retain six bottom destinations; the left drawer contains task organization, feature shortcuts, theme, language and account actions. Notification infrastructure is not implemented, so no nonfunctional notification button is added.

The task workspace has three content columns beside the rail: organization (230 px), task list (flexible), and selected task details (330 px). At available widths below 1100 px details use the existing task editor dialog; below 850 px organization opens in the left drawer. Each column scrolls independently. Add task sits above the task list and opens the validated local-first editor. Sorting, priority filtering and bulk actions remain available. Domain persistence and sync are unchanged.

Task quick entry now uses an inline title field with Enter submission, date and priority controls, and an expand action. Reusable calendar and flag menus are shared by creation, editing and desktop details, retaining MindFlow's Material theme and accessible labels. Advanced scheduling (time/duration/reminder/repeat) remains pending domain support.

Task quick entry places the date/time trigger at the trailing end of its input. The shared calendar includes an optional time picker and independent time clearing. Task details now contain directly editable title/notes and immediate scheduling, completion, priority, list and matrix controls, plus local save/error status. The explicit Edit action is removed; compact layouts use the same details component in a dialog.

Organization now exposes Space → Project → Task → Subtask, with no separate
Folder/List/Group/Section/Workspace level. Global views remain projections. Space
selection includes Project tasks; Project selection includes nested subtasks.
Task rows indent at most three levels. Details list immediate subtasks with
navigation, allow selecting a parent/location and show only direct tags as chips.
Inherited tags expand on demand with their source. Space/Project/Tag editors
separate archive from project status. Include-archived and archived-tag controls
keep old work discoverable and restorable. New Projects require a Space; task
quick entry still works in Inbox with no organization setup.

The sync icon sits next to the profile controls in the desktop rail and mobile drawer, without a status/pending text row. Tasks omits the top page header to maximize workspace height; other screens retain their page headers. Tasks keeps its organization drawer trigger in the task toolbar. Normal sync uses the default icon color; offline, sign-in required and conflicts use error red. A badge counts distinct conflicting tasks. The tooltip retains status and pending details. When sign-in is required, clicking opens the sign-in page directly, including when conflicts exist. Otherwise clicking opens conflicts or starts manual sync as appropriate.

The organization sidebar exposes Today, Next 7 days, Inbox and Notes. Spaces,
Projects and Tags each have a collapsible heading, a direct archive visibility toggle, and a separate + button to the right for creation. The archive icon is outlined when hidden and filled with a selected background when shown; its tooltip offers Show archived or Hide archived. Spaces, Projects and Tags each have independent archive visibility. Selecting an archived Space or Project includes its tasks and notes without changing another section’s toggle. Archived records remain hidden initially. Record
editing and archive/restore actions use row overflow menus. All tasks and
Completed remain accessible through My tasks overflow. Notes projects existing
canonical note records; creation still requires a Space or Project in the editor.
Next 7 days covers today through six days later using local calendar dates.

Sign-out confirmation explains that account data stays on the device and offers Cancel and Sign out. When pending changes exist, it also shows their count and Sync first. The dialog supports English and Vietnamese; signing out retains local data and the outbox.

Task workspace columns have draggable 8 px dividers. Organization adjusts between 180–420 px. The task list and details split the remaining width equally by default; dragging the details divider sets a custom width, with at least 280 px for details and 360 px for the task list. Focus a divider and use Left/Right to move it; accessible increase/decrease actions are supported. Widths remain in shell state during navigation and adapt to window resizing; compact drawer/dialog breakpoints remain unchanged. Widths reset on app restart.

Divider dragging uses global pointer movement and accumulates width changes independently of render frames, so moving the divider does not distort pointer deltas or drop rapid updates.
