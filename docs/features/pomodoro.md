# Focus

Configurable durations (5, 15, 25, 45, 60 minutes), focus/short-break/long-break kinds, start/pause/resume/finish. Sessions persist duration, elapsed seconds, UTC start and running anchor; all writes use the domain/outbox transaction and sync.

After restart the first calculation recovers elapsed time from UTC. Foreground advancement uses Stopwatch monotonic elapsed time and ignores subsequent wall-clock jumps. Values are bounded by duration. While viewing Focus, reaching zero persists completion automatically. Returning after a deadline also completes the session. No OS background execution or exact notification guarantee is claimed. Cold-start recovery under a changed clock is necessarily approximate and clamped. Configuration defaults and automatically cycling breaks, linked tasks, daily totals and richer statistics remain unfinished.
