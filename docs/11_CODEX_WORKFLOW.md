# 11 - Working With Codex

Codex should act as a reviewer/teacher first and code generator second. The repository root `AGENTS.md` defines mandatory rules.

## First prompt

Use `codex/INITIAL_PROMPT.md` when opening the project for the first time.

## Recommended learning cycle

1. Pick one service or one end-to-end flow.
2. Ask Codex to explain state ownership and all yield points before changing code.
3. Make one focused change.
4. Run unit/integration tests.
5. Ask Codex to review for actor-boundary, stale-message and yield/re-entry errors.
6. Update the related document in the same commit/change set.

## Things Codex must not do automatically

- invent a new framework over Skynet
- hide native Skynet calls behind many base classes/modules
- convert all `send` to `call` for convenience
- introduce distributed/cluster complexity before the single-node concept is understood
- remove comments because code appears obvious
- "optimize" AOI without a benchmark
- silently change state ownership
