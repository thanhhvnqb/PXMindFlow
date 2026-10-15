# Search

Offline reactive FTS5 across canonical tasks (including notes), lists and habits; terms are safely quoted into prefix queries, results exclude tombstones and are bounded to 200. Editing a result opens the canonical editor. SQLite triggers update the index atomically with records. Native index updates/tombstones are tested. A parameterized substring fallback is used if FTS5 creation is unsupported. Browser runtime needs a smoke test. Advanced filters and dedicated result navigation remain unfinished.
