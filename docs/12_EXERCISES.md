# 12 - Exercises

Recommended order:

1. **Trace login manually.** Add temporary logs containing `skynet.self()`, source and session in Watchdog/PlayerMgr/Agent. Explain each address.
2. **Two clients.** Start player 10001 and 10002; move one across view range and verify enter/move/leave pushes.
3. **Create a race intentionally.** Temporarily remove PlayerMgr login queue, add a yield before publishing `players[id]`, then launch duplicate logins and observe why two Agents are possible.
4. **AOI grid-size benchmark.** Compare grid sizes 10/20/40 while keeping view radius 18. Explain why grid_size < view_radius invalidates the current fixed 3x3 assumption.
5. **Monster AI.** Move one monster once per second through Scene and update player visibility correctly.
6. **Dirty persistence.** Add dirty flag + 30-second snapshot without blocking every gameplay operation.
7. **Critical currency operation.** Design a durable gold purchase path and explain idempotency/retry semantics.
8. **Scene lines.** Create two instances of scene 1 and add a simple routing policy.
9. **Metrics.** Expose Scene stats and PlayerAgent count via a diagnostic service.
10. **C optimization decision.** Benchmark first, then decide whether AOI needs a C module; document the evidence rather than assuming Lua is the bottleneck.
