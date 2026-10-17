# Spaces, projects and tags

## Audit and compatibility mapping

The existing app stores tenant-keyed JSON envelopes, not dedicated domain tables.
`task_list` is now a Space; `list_id` remains the compatible direct Space reference.
There are no Folder, Group, Section, tag or project records in the old schema.
No user records, versions, pending operations, change history or IDs are rewritten.
Old payloads remain accepted; older clients do not understand the new organization
semantics and must be upgraded before editing newly organized records. New fields
require the updated server before using the updated client. No Workspace level is introduced.

## Canonical placement

A root task has either `list_id` (direct Space), `project_id`, or neither (Inbox).
A project requires `space_id`. Subtasks use the compatible `parent_id` field
(the wire spelling of parent_task_id), with neither placement field: their context
is derived from their parent recursively. Moving a root therefore moves its entire
subtree without bulk edits. Moving a subtask detaches it or chooses another parent.
Cycles, missing/deleted parents, cross-account references and ambiguous placement
are rejected locally and on push. No depth limit is imposed on storage; details
show immediate children and navigation keeps each view shallow.

Direct many-to-many tags use a unique array `tag_ids` on each Space, Project or Task
envelope; this is a set of references, not embedded tag copies. Effective tags are
computed from the actual Space → Project → ancestor tasks → Task chain, with source
information. Flat tag records have independent `archived_at`. Existing bindings to
archived tags remain valid; assignment suggestions omit archived tags.

Projects have active/on_hold/completed/cancelled status independently of archive.
Archive is a nullable UTC instant and never a tombstone. Effective archive derives
from actual ancestors. Active task projections exclude archived ancestry; archive
mode includes it. Search includes archived records so they remain discoverable.
Deleting a referenced organization record is rejected; archive it instead.

## Persistence and migrations

Local v3 and server 0003 add expression indexes for organization references.
Existing envelope identity/owner constraints remain. JSON reference integrity is
validated transactionally in repositories and under the account lock on the
server; dedicated relational foreign keys remain a known architecture limitation.
No domain/outbox data migration is necessary for the compatible rename. Tags and
organization changes use the existing atomic local outbox and conflict protocol.

Read-only development data audit (2026-10-17): the existing `pxmindflow` database
contains two task records and no organization records. Only entity-type counts
were read; no task content or credentials were exported. The development database
and its volume were not migrated or replaced during implementation.
