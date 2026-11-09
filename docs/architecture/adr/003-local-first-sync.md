# ADR-003 — Local-first client with outbox sync and server-authoritative progression

Status: Accepted · 2026-11-04

## Context
Users must create and complete quests offline (commutes, poor connectivity, travel) and see
results on all devices. Guild challenges make progression competitive enough that clients
cannot be trusted to write XP.

## Decision
- The client's source of truth for UI is a local SQLite database via **Drift** (native SQLite
  on mobile/desktop, `sqlite3.wasm` + web worker on the web). The UI only reads local data.
- Every mutation is written locally and appended to an **outbox**; a sync worker pulls by
  cursor, pushes in order and pulls again, on sign-in, shortly after each local change and
  every two minutes. Realtime only signals guild-hall changes (feed events, comments,
  challenges), which trigger a refetch; personal tables are not published.
- Quests/subtasks: field-level last-writer-wins using a hybrid logical clock.
  Completions and ledger entries: append-only, idempotent by client UUID.
- **Progression is server-authoritative.** Offline, the client computes a provisional
  result with the same engine (ADR-004) and labels it "will be confirmed"; the server result
  supersedes it on sync. Typical deltas are zero because the heuristic is also the server's
  fallback; with AI enabled they are usually small and are animated, not hidden.

## Consequences
+ The app is fully usable with no backend at all (guest/demo mode).
+ No lost completions; retries are safe.
− Schema changes require coordinated client migrations (Drift `schemaVersion`) and server
  migrations; both are versioned and tested.
