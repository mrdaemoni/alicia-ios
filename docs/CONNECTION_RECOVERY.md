# Connection recovery candidate — October 24, 2026

The banner's automatic retry previously read `modeState`, whose raw request
returned idle/zero on failure without reporting connection status. A successful
retry therefore did not clear stale errors or reload failed home fields. The
briefing's Check again action refreshed only its own reading.

Both entry points now use one coalesced AppStore recovery task. Its authenticated
`GET /api/mode` must decode before it counts as success. Transport/HTTP failures
and 401/403 retain their existing retry/error handling; a malformed 200 response
does not mark the connection healthy. Ordinary reads also report success only
after decoding. No fallback thinking mode is used as a connectivity receipt.

After success, fresh intelligence, briefing and episode reads run concurrently.
Missing refresh values retain existing content. Episode acceptance still uses
the existing pending-selection and revision guards. Recovery does not run full
startup, send a message, resume an outbox, initiate playback, write mode settings,
or schedule a thought-return notification. An older busy briefing request cannot
silently skip the recovered read. The Check again label stays Checking while the
shared recovery is active, including when the banner has already disappeared.

A settings revision prevents a stale intelligence read from replacing a setting
saved while that read waited; recovery skips an active mode save. Overlapping
automatic/manual retries share the same probe and reload. Completion releases
that task so a later retry can run. Removing the banner does not cancel its
in-flight content reload.

`scripts/test_connection_recovery.py` compiles actual Swift transport/store methods
against loopback-only HTTP fixtures and suspended fake IO. It checks failure and
recovery, transport/authorization/decode errors, overlapping retries, later
retries, settings races, retained content and caller cancellation. It sends no
production request or POST. Existing startup, conversation delivery, context and
briefing harnesses remain relevant compatibility checks.

Base: PR53 source `c2f16abb2f2b398adfc289f128f9afd275a61c80`, recorded TestFlight50
source and paired-phone installed build50. Canonical main is older and is not
silently substituted. PR49 and the separate study-note candidate overlap core
files and require serial integration; PR54 voice changes are outside this diff.

This is an unshipped candidate. Separate approval is required for any merge or
TestFlight release. Installed-phone recovery is not established by simulator or
fixture checks. Device-specific past HTTP failure details are not inferred from
the client retry defect; no credentials, overrides or network settings are changed.
