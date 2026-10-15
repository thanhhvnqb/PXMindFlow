# Database

Local schema v2: records(id,kind,payload,version), outbox(position,operation_id,entity_id,kind,operation,payload,base_version,sent), conflicts(entity_id,kind,local,remote,reason), sync_state(key,value). Record/conflict keys are composite; operation_id unique; outbox position autoincrements. Each account has a separate SQLite database. UUIDs originate on the client. Domain mutations and outbox insertions share a transaction.

Server migration 0001: users with unique normalized email and per-account sequence; hashed refresh tokens with expiry/revocation; tenant-keyed records; tenant/operation idempotency rows; tenant/sequence change ledger. FK to users on all owned tables. Payload relations are validated within the owner; database domain FKs still need dedicated tables.

Envelope payloads contain created_at, updated_at, deleted_at in UTC. Due dates are ISO local calendar dates, not UTC midnight. Habit check-ins identify their local date and captured IANA timezone. Focus anchors are UTC instants with persisted elapsed seconds; foreground advancement is monotonic; cold-start recovery after a changed wall clock remains a bounded approximation.

No hard deletion or tombstone cleanup is enabled. Migration v2 adds an FTS5 record index maintained by insert/update/delete triggers. Search queries are parameterized, bounded to 200 results and reactive. If the SQLite backend lacks FTS5, a parameterized substring fallback is used. Native FTS5 is tested; browser runtime compatibility is not yet smoke-tested. Dedicated domain indexes remain unfinished. Recurrence is deliberately unavailable until occurrence keys, timezone rules and completion storage can be tested.

Server migration 0002 adds shared auth rate windows (hashed client address, minute bucket, count). Counters survive API replica changes. An expiry job for these non-domain counters remains to implement.
