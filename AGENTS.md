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

## 写作风格要求（强制门禁）

面向学习者的课程、专题文档、代码说明和工程讲解，必须使用自然、克制、像有实际经验的人写出来的中文，不得使用典型的 AI 写作腔。

1. 先讲具体事实、判断和结论，不要用空泛的开场白铺垫。
2. 不要为了显得完整而强行分成大量小标题，不要每两三句话就列一组项目符号。
3. 避免机械使用“首先、其次、再次、最后”“总的来说”“综上所述”“值得注意的是”“需要强调的是”等连接词。
4. 禁止频繁使用以下句式：
   - “不是……而是……”
   - “不仅……更……”
   - “这意味着……”
   - “本质上……”
   - “真正的……”
   - “关键在于……”
   - “从某种意义上说……”
   - “既……又……”
5. 不要堆砌正确但无用的废话，不要反复换一种说法重复同一个结论。
6. 不要为了制造节奏而大量使用短句、排比句、反问句和口号式表达。
7. 不要擅自拔高主题，不做情绪升华，不写“这不仅是……更是……”式结尾。
8. 长短句自然交替。能用一段话讲清楚的内容，不要拆成五六个条目。
9. 技术内容要解释因果关系和实际运行过程，不要只罗列概念、术语和优缺点。
10. 如果缺少可靠信息，直接说明不确定，不要用听起来合理的内容填补空白。
11. 写完后自行检查并删除：
    - 空洞的开场和总结；
    - 重复结论；
    - 不提供新信息的过渡句；
    - 模板化金句；
    - 无必要的小标题。
12. 最终文字应当像一位熟悉该领域的人在认真向另一位成年人说明问题，而不是像培训材料、营销软文或标准化 AI 答案。
13. 写作时以“实际执行过程”为主线：
    - 从一个真实入口、命令、请求或故障现象开始，沿代码实际发生的先后顺序讲解；
    - 先说明一个请求从哪里进入、经过哪些 Service、在哪里挂起、在哪里恢复、数据由谁持有；
    - 明确每一步对应的源码文件和函数，以及当时所在的 Process、Thread、Service、Lua State 和 coroutine；
    - 顺着 Message Path 说明参数如何传递、状态由谁读取或修改、哪里会 yield、恢复后哪些数据可能失效；
    - 执行过程跨越 C Runtime、Lua Runtime 和业务 Service 时，按调用或消息到达顺序切换层次，不要来回跳跃；
    - 术语和 API 在执行过程中第一次出现时就地解释，并立刻关联当前工程中的具体对象；避免先堆放脱离上下文的名词表；
    - 讲到返回值、Response、错误或退出时，继续追踪它最终回到哪里，以及调用方随后执行什么；
    - 示例优先采用仓库中可以运行、断点和验证的真实路径。若使用简化伪代码，应说明省略了哪些环节，不能让伪代码改变真实语义。
14. 每介绍一个概念，都要说明它解决了什么问题、内部大致怎样工作、在工程中如何使用、容易踩什么坑。不要把“Actor、coroutine、消息驱动、高并发、解耦”等词当成解释本身。
15. 可以结合传统 C++ + Lua MMO Server 作对比，但只在对理解有帮助时比较，不要每一节都机械对比。
16. 所有代码必须标明完整仓库路径，并解释关键代码为什么这样写。这里的“完整仓库路径”指从仓库根目录开始的路径，不使用只有文件名、读者无法定位的写法。
17. 不要罗列一组 API 后让读者自行推断它们之间的关系。API 应放进具体调用链或消息路径中讲清调用方、接收方、参数、返回方式、yield 行为和失败表现。
18. 对性能、并发和内存方面的结论必须给出成立条件，包括负载特征、Service 划分、是否发生 yield、队列长度、数据规模或测量环境中与结论相关的部分，避免绝对化表述。
19. 课程文档的口吻应当接近一位做过实际游戏服务器的主程写给同行的内部培训资料：默认读者具备工程经验，给出足够的运行细节和判断依据，不用初学者话术稀释技术内容。

## Test rules

Run `./scripts/linux/test.sh` after behavior changes. AOI algorithm changes must also run `./scripts/linux/benchmark_aoi.sh` and report before/after numbers. Add a regression test for any bug found.

## Do not

- upgrade Skynet/Lua silently
- switch to an unofficial native Windows fork
- replace Sproto without a dedicated lesson/migration rationale
- remove learning comments merely to shorten files
- introduce Redis/cluster/Kafka/etc. without a concrete lesson need
- hide failures with broad fallback/catch logic
