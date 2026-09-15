# AGENTS.md - Codex rules for this learning repository

## P0 purpose

This repository exists to teach Skynet by building a complete MMO server/client path. Documentation, explanatory comments, tests and explicit actor/state ownership are P0 requirements, not optional polish.

## Learner profile and training target

- The learner is an experienced MMO Server C++ lead programmer and is already familiar with Lua. Do not default to beginner explanations of networking, C++, Lua syntax, AOI, persistence, or ordinary server architecture.
- The target is production-working competence with Skynet: the learner must be able to evaluate architecture, review coroutine correctness, diagnose runtime failures, profile bottlenecks, and lead a real project rather than merely run this sample.
- Explain Skynet by mapping it to familiar C++ MMO Server concepts where useful, but explicitly identify semantic differences. In particular, never equate a Skynet Service with a permanently non-reentrant single-thread game loop: a Service coroutine can yield and other messages can mutate its state before it resumes.
- Training order starts with the real toolchain: source/bootstrap, native build and artifacts, configuration/bootstrap, Lua and C debugging, observability and failure diagnosis. Continue with Runtime scheduling/message internals, coroutine correctness, service boundaries, production engineering, and performance.
- Do not impose a fixed-day, fixed-week, or crash-course schedule. Progress incrementally from observable behavior to implementation internals, use capability-based checkpoints, and move on only after the current layer can be explained, operated, debugged, and verified. Keep explanations accessible without sacrificing source-level or production depth.
- Do not present ad-hoc print logging as a sufficient debugging system. Teach and build an appropriate combination of debugger, deterministic tests, structured logs, trace/context IDs, Service state inspection, message-queue/latency metrics, record/replay, profiling, Core Dump, and GDB. Explain which tools are safe in personal, shared, staging, and production environments.
- Prefer established upstream debugging tools. Do not create a custom Lua debugger or silently replace official Skynet with a debugger-specific fork. LuaPanda integration must remain opt-in and absent from normal/test/production startup paths.
- Explanations for important paths should identify the relevant source files, process/thread/Service/coroutine context, message path, yield points, state ownership, failure mode, and verification method—not only list commands or APIs.
- Except for established technical terms, commands, identifiers, and quoted upstream material, learner-facing documentation and explanations should be written in Chinese.

## Baseline

- Skynet: v1.8.0
- Lua: Skynet bundled modified Lua 5.4.7
- Server runtime: Linux or Windows through WSL2
- Protocol: Sproto + 2-byte big-endian length framing
- Default storage: memory; optional MySQL
- Development Lua debugger: LuaPanda 3.3.1 (`e3ac3d3314f24cf939c36cac5b7dc1f2ed6ee129`) with LuaSocket v3.1.0, enabled only for an explicitly selected Service

## Mandatory review rules

Before modifying a service, identify:

1. Which state the service owns.
2. Every possible coroutine yield point.
3. Whether state read before a yield can become stale after resume.
4. Whether `call` is actually required or `send` is sufficient.
5. Whether the change creates an unnecessary central proxy/hot Actor.
6. Whether stale fd/service/timer messages need a generation/version check.

## Architecture rules

- KISS. Do not build a second Actor/framework layer above Skynet.
- Composition/modules over inheritance-style base-service hierarchies.
- A PlayerAgent owns persistent player state; Scene owns real-time spatial/combat state.
- Same player's client business operations remain serialized unless the change explicitly proves safe parallelism.
- Manager services handle lifecycle/routing; avoid routing every high-frequency message through managers forever.
- Avoid deep synchronous RPC chains.
- Do not turn every module into a Service.
- Optimize from profiling/benchmarks, not from assumptions about Lua.

## Documentation rules

Any meaningful behavior/architecture change must update the matching file in `docs/` in the same change. New Skynet APIs must be explained before assuming the learner knows them. Important code should contain comments explaining WHY, especially yield/race/state-ownership decisions.

## Test rules

Run `./scripts/linux/test.sh` after behavior changes. AOI algorithm changes must also run `./scripts/linux/benchmark_aoi.sh` and report before/after numbers. Add a regression test for any bug found.

## Do not

- upgrade Skynet/Lua silently
- switch to an unofficial native Windows fork
- replace Sproto without a dedicated lesson/migration rationale
- remove learning comments merely to shorten files
- introduce Redis/cluster/Kafka/etc. without a concrete lesson need
- hide failures with broad fallback/catch logic
