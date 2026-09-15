Review the current changes under the rules in AGENTS.md. Prioritize correctness over style.

Specifically audit:
- Skynet coroutine yield/re-entry bugs.
- duplicate PlayerAgent/Scene creation races.
- stale fd/connection/timer messages.
- state ownership violations between PlayerAgent and Scene.
- misuse of call vs send and deep RPC chains.
- AOI enter/leave/move set consistency.
- monster death/respawn visibility consistency.
- persistence ordering/data-loss risks.
- tests/docs that should change with the code.

List P0/P1/P2 findings. For every finding, name the file/function, explain the failure scenario and propose the smallest fix. Do not implement until asked.
