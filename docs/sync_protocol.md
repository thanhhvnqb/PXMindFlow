# Sync protocol v1

POST /api/v1/sync/push accepts up to 100 mutations. Fields: operation_id, device_id, entity_type, entity_id, operation, base_version, payload. Client-generated UUIDs identify records and operations. Each push locks the authenticated user's row, checks durable idempotency result, checks authoritative version, validates references under that owner, updates a record and appends a change in one transaction. Idempotency fingerprints reject reuse with different input. A duplicate returns the original result plus duplicate=true, including original conflicts. Conflicts are explicit, never last-write-wins. Deleted records cannot silently resurrect.

Per-account sequence allocation occurs under the same row lock as commit: an uncommitted lower sequence cannot be overtaken. Pull is tenant-scoped, ordered, bounded, includes tombstones and returns next_cursor/has_more. cursor ahead produces 409; no retention/expiration exists because the log is retained indefinitely. Cursor 0 is bootstrap.

Client serializes sync cycles. Each operation is frozen as sent before I/O. Identical retry after timeout/crash preserves operation_id and request. ACK removes exactly that operation transactionally. Later unsent operations receive its canonical version; latest local payload remains visible. Client pushes before pulling. Remote records with pending edits enter attention/conflict storage, never overwrite local records. Page application and cursor advance are atomic; non-monotonic pages fail without advancing.

Conflict UI offers Review differences, Keep mine and Keep server. Explicit resolution supersedes the entity's pending operations. Keep mine emits a fresh operation against the remote version. If server deleted a record, keeping a live local copy creates a new UUID rather than resurrecting a tombstone. Resolution against another newer remote version may conflict again. Independent fields currently require user resolution; no speculative auto-merge.

Worker retries with capped exponential backoff and jitter; foreground and local changes trigger sync. Logout retains all local data/outbox with explicit user confirmation. Secure tokens rotate after access expiry. Authentication failures surface sign_in_required. Clicking the sync button in sign_in_required opens sign-in directly through the existing account-close flow, taking precedence over conflict review; account SQLite data and pending changes remain retained. The account menu keeps its separate sign-out confirmation. cursor_ahead resets only the cursor to zero and re-reads retained history; local records/outbox are preserved. No background execution guarantees. Device registration/revocation, cursor expiry, complete common-base diffs, automatic reconnect detection and all required recovery tests remain tracked work. Never enable retention before implementing bootstrap preserving pending edits.

Conflict snapshots track subsequent local edits. Resolution reads the latest local payload and conflict in its transaction, so edits made while attention or a dialog is open are retained. Habit check-in UUIDv5 identity derives from habit/date/captured timezone; the server verifies it and version-conflicts duplicate creates rather than counting twice.

Timed-task payloads include optional UTC `due_at`; it uses the same atomic outbox, canonical ACK, pull and explicit-conflict paths as other task fields. Inline details send field patches through a repository transaction that reads the latest local task, preventing stale UI snapshots from overwriting unrelated local fields. There is no separate calendar or scheduling record.

Organization records (`task_list` as Space, `project`, `tag`) share this same
protocol. Create referenced tags/Spaces before Projects/tasks and parents before
subtasks. Placement and tags are editable fields, so concurrent placement/tag
edits use the existing explicit version-conflict queue. Subtask context and
inherited tags are derived at read time; moving a parent or archiving a Space
never enqueues synthetic child updates. Deletes of referenced organization
records fail with `record_in_use`; Task subtree deletion queues deepest children
first in one local transaction. A remote child edit can conflict during that
sequence; dependent parent deletion then remains blocked rather than orphaning
that child. Archive retains every record and binding and is independent of
project lifecycle status. Upgrade the API before using the new client fields.

Validation rejection recovery: a missing snapshot on `validation_failure` means
unknown server state, not record absence. Retrying keeps the local record, UUID,
acknowledged version and latest edits, and replaces the rejected operations with
a fresh operation ID. Version-zero live records retry as creates; acknowledged
records retry as updates. Legacy unprefixed invalid_payload conflicts follow the
same path. Keep server is unavailable without an authoritative snapshot; the
repository rejects that action rather than deleting local data. Updated API
validation results include the current authorized snapshot when one exists.
Rejected operation results remain immutable/idempotent, so updating the server
requires retrying with a fresh operation ID rather than replaying cached rejection.
