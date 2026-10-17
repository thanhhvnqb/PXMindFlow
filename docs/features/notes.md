# Markdown notes

## Persistence and organization

Task notes retain the existing `notes` field. Select a Space or project in Tasks
to create multiple titled notes, edit them or delete with confirmation. Each
`note` is a separate client UUID envelope with exactly one `list_id` (Space) or
`project_id`. Content is limited to 20,000 source characters and the required title
to 500. Notes participate in offline search and inherit archive context. Parents
cannot be deleted while live notes reference them.

All writes use the existing atomic SQLite/outbox transaction, tenant reference
validation, version checks, idempotency, tombstones and conflict queue. No schema
migration, dependency or record rewrite is needed. Upgrade the API before using
the notes client. Older clients cannot edit independent note records.

## Rendered editing

Notes open in an editable rendered view. Typing, deletion, paste, newlines and
composing text update canonical Markdown through the existing save callback. The
Flutter rich text controller tracks inline marks and block prefixes and emits
balanced delimiters when editing. The Markdown code / Rendered view button
switches modes without changing source or adding an outbox operation.

Supported formatting includes text, headings 1–3, bullets, numbered lists, check
items, quotes, bold, italic, strikethrough, links and yellow highlight. Links show
the label; their destination remains in source. This is a limited Markdown subset,
not full CommonMark: tables, code fences and arbitrary HTML are not rendered.
Checklists use accessible checkboxes with editable row text; checking changes
only `[ ]` / `[x]` and completed text is struck through. Selection across separate
checklist rows is unavailable. Ordinary notes use one multiline rendered input.

## Floating formatting menu

Select text in either mode to open the horizontal formatting toolbar. Its style
button reflects the current heading/list/check/quote and the style popup marks
the selected type. Mixed-block selections reflect the first line. Copy and Select
all are omitted; normal keyboard clipboard shortcuts remain available.

Highlight toggles `==text==`, using only yellow background with dark text for
contrast. Multiline highlight is applied separately per line, preserving block
prefixes. Text colors and color-HTML rendering have been removed. Existing color
spans remain literal text; no saved or unsent content is silently rewritten.

The toolbar closes when selection becomes collapsed/invalid or on outside
interaction. Root context-menu overlays avoid placing interactive controls inside
EditableText's follower layer, which caused a hover paint-transform assertion.
Selection/source snapshots protect formatting from stale offsets. Native menu
requests use the same overlay. Editors remove their overlays when disposed.
On Web, the browser context menu is disabled while editors are mounted so Flutter
can display this menu, and its prior state is restored after the last editor closes.
