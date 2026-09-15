# Skynet MMO Learning Project

A deliberately small but end-to-end MMO server/client project for learning **Skynet v1.8.0 + modified Lua 5.4.7** through real code rather than isolated API samples.

The project keeps the architecture production-shaped while leaving some systems intentionally simple so each lesson remains inspectable.

## What is implemented

- Official Skynet `gate.lua` + custom Watchdog connection lifecycle.
- Sproto `C2S/S2C` protocol and 2-byte big-endian TCP framing.
- One online player = one `PlayerAgent` service.
- Duplicate-login protection and connection-generation (`fd + connection_id`) checks.
- Per-player `skynet.queue` serialization around client business requests.
- `SceneMgr` + one `Scene` Actor per map instance.
- 3x3 Grid AOI with exact-radius filtering.
- Player enter/leave/move visibility diffs.
- 服务端权威地图边界与 Token Bucket 移动速度校验。
- Monster spawn, HP broadcast, deterministic combat and respawn.
- `sharedata` static game configuration.
- Storage abstraction with zero-dependency memory mode and optional MySQL worker pool.
- Lua learning client supporting login/ping/move/attack/logout.
- Unit tests, real network integration smoke test and AOI benchmark.
- Linux scripts and Windows/WSL2 PowerShell wrappers.
- VS Code/WSL2 tasks、Lua Language Server、Skynet Debug Console 与 GDB 调试配置。
- Codex collaboration rules and learning prompts.

## Platform policy

Skynet v1.8.0 does **not** provide an official native Windows build target. This repository therefore supports:

- **Linux:** native build/run.
- **Windows 10/11:** WSL2 build/run, launched directly through the provided PowerShell scripts.

This is intentional. Using an unofficial Windows Skynet fork would teach platform-porting differences instead of mainstream Skynet.

## Fastest start: Linux / WSL2

```bash
./scripts/bootstrap_skynet.sh
./scripts/linux/build.sh
./scripts/linux/test.sh
./scripts/linux/run_server.sh
```

Open another terminal:

```bash
./scripts/linux/run_client.sh
```

Useful client commands:

```text
ping
move 101 100
attack 100001
logout
```

## Fastest start: Windows PowerShell

先按照 `docs/09_WINDOWS_WSL2.md` 完成 Ubuntu 安装、首次启动与 VS Code WSL 工作区配置，再从仓库根目录执行：

```powershell
.\scripts\windows\bootstrap.ps1
.\scripts\windows\build.ps1
.\scripts\windows\test.ps1
.\scripts\windows\run_server.ps1
```

Second PowerShell window:

```powershell
.\scripts\windows\run_client.ps1
```

课程主线统一从 `docs/COURSE_CATALOG.md` 进入，完整教学只分四课，不设固定学习周期。第一次配置机器时配合 `docs/00_READ_ME_FIRST.md` 操作；其他编号文档是专题手册，不要求按编号逐份阅读。

Lua 业务图形调试使用 VS Code + LuaPanda。运行 task `Skynet MMO：准备 LuaPanda 调试环境` 后，在“运行和调试”中选择 Scene 或 PlayerAgent；完整过程见 `docs/16_DEBUGGING.md`。正常服务器、自动测试和生产配置不会加载 LuaPanda。

第一课使用 `docs/Skynet第一课_启动链源码导读_重写版.pdf`；第二课使用 `docs/Skynet第二课_Service模型与Actor架构.md` 或同名 PDF，进入 Service、Mailbox、Worker、coroutine 重入、状态所有权和 Actor 边界。

## 当前新增 P0

服务端现在拥有并校验角色的实时移动：越界和超速请求不会进入 AOI，也不会污染持久化坐标。设计、Coroutine/yield 审查和错误语义见 `docs/15_P0_AUTHORITATIVE_MOVEMENT.md`。
