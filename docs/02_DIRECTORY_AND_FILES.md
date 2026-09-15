# 02 - Directory and File Map

## Root

- `README.md` - quick start and project scope.
- `AGENTS.md` - repository instructions for Codex.
- `Makefile` - Linux/WSL convenience targets.
- `compose.mysql.yml` - optional MySQL 8.4 development container.

## 学习主线文档

- `docs/COURSE_CATALOG.md` - 四课唯一课程目录与按能力验收的学习路线。
- `docs/00_READ_ME_FIRST.md` - 首次构建、运行和调试的环境操作入口。
- `docs/16_DEBUGGING.md` - LuaPanda、Debug Console、GDB 与生产诊断边界。
- `docs/Skynet第一课_启动链源码导读_重写版.pdf` - 第一课：从 Native Build Artifact、配置解析到 `service/main.lua` 的完整启动链。
- `docs/Skynet第二课_Service模型与Actor架构.md` - 第二课可编辑教材；同名 PDF 是发布版。
- `docs/Skynet第三课_完整MMO业务闭环与一致性.md` - 第三课可编辑教材；发布版位于 `output/pdf/`。
- `docs/Skynet第四课_生产工程故障诊断与性能.md` - 第四课可编辑教材；发布版位于 `output/pdf/`。

## output

- `output/pdf/Skynet第三课_完整MMO业务闭环与一致性.pdf` - 第三课 41 页 A4 发布版。
- `output/pdf/Skynet第四课_生产工程故障诊断与性能.pdf` - 第四课 38 页 A4 发布版。

## .vscode

- `settings.json` - Lua 5.4 与项目/Skynet module 搜索路径。
- `tasks.json` - 拉取、构建、测试、服务器、客户端、LuaPanda 和 Debug Console 快捷任务。
- `launch.json` - LuaPanda 的 Scene/PlayerAgent 图形调试配置，以及 Skynet Runtime 的 GDB 配置。
- `extensions.json` - Remote WSL、C/C++、Lua Language Server 与 LuaPanda 推荐清单。

## config

- `config/game.lua` - normal development configuration, port 8888, memory storage by default.
- `config/test.lua` - isolated integration-test configuration, port 18888.
- `config/debug_luapanda.lua` - 复用正常配置，仅为显式目标 Service 增加 LuaPanda 路径和 Preload。

## service

- `service/main.lua` - application bootstrap. Creates dependencies and opens Gate last.
- `service/protocol/protoloader.lua` - parses Sproto and stores slots 1/2.
- `service/config/config_service.lua` - publishes static configuration through `sharedata`.
- `service/auth/auth.lua` - development token verifier.
- `service/gateway/watchdog.lua` - connection state machine and pre-login handling.
- `service/player/player_mgr.lua` - player id -> unique Agent mapping; sharded login locks.
- `service/player/player_agent.lua` - player state, C2S dispatch, reconnect binding, serial business queue.
- `service/scene/scene_mgr.lua` - scene lifecycle and creation race protection.
- `service/scene/scene.lua` - spatial authority, AOI visibility, monsters and combat.
- `service/storage/storage_mgr.lua` - storage worker pool/router.
- `service/storage/memory_worker.lua` - zero-dependency learning persistence.
- `service/storage/mysql_worker.lua` - optional MySQL implementation.

## lualib

- `lualib/protocol/schema.lua` - C2S/S2C Sproto definitions.
- `lualib/protocol/frame.lua` - `>s2` TCP frame encoder.
- `lualib/config/game_data.lua` - static scene/monster config.
- `lualib/scene/aoi_grid.lua` - Skynet-independent 3x3 spatial index.
- `lualib/scene/combat.lua` - Skynet-independent combat math.
- `lualib/scene/movement.lua` - 无 Skynet 依赖的地图边界与 Token Bucket 移动校验。
- `lualib/debug/luapanda_preload.lua` - Dev-only LuaPanda 注入点；非目标 Service 立即返回。

## client

- `client/test_client.lua` - interactive and `--auto` integration client.

## tests

- `tests/unit/test_aoi_grid.lua` - insert/move/remove/neighborhood behavior.
- `tests/unit/test_combat.lua` - range/damage math.
- `tests/unit/test_movement.lua` - 越界、超速、额度补充与容量上限。
- `tests/unit/run.lua` - unit test entry point.
- `tests/integration/smoke.sh` - starts real Skynet, logs in, attacks and kills a monster.
- `tests/benchmark/aoi_bench.lua` - candidate-query benchmark.
- `tests/tooling/test_luapanda_runtime.sh` - 验证 LuaSocket 产物布局及 Bundled Lua 5.4.7 加载兼容性。
- `tests/tooling/test_luapanda_preload_order.lua` - 保证 LuaPanda 先包装 Coroutine，再加载会缓存 `coroutine.create` 的 Skynet Runtime。
- `tests/tooling/test_client_stdin.lua` - 保证交互客户端只消费 `client.socket` 的 stdin Queue，不与其 C pthread 竞争 TTY。
- `tests/tooling/test_windows_wslpath.ps1` - 防止 PowerShell 5.1 向 `wslpath` 传递反斜杠路径时发生转义回归。

## scripts

- `scripts/bootstrap_skynet.sh` - fetches pinned v1.8.0 recursively.
- `scripts/bootstrap_luapanda.sh` - 拉取固定的 LuaPanda 3.3.1 与 LuaSocket v3.1.0。
- `scripts/linux/*` - build/run/test/benchmark.
- `scripts/linux/build_luapanda.sh` - 针对 Skynet Bundled Lua Header 构建 `socket.core`。
- `scripts/linux/run_luapanda_server.sh` - 设置单一目标 Service 并启动 Dev-only Debug 配置。
- `scripts/linux/debug_console.sh` - 通过 `nc` 连接 Skynet Debug Console。
- `scripts/docs/build_course_pdf.py` - 将课程 Markdown 渲染为统一 A4 PDF；需要 WSL 的 `python3-reportlab` 与 `fonts-wqy-microhei`。
- `scripts/windows/*` - PowerShell wrappers that execute the Linux scripts through WSL2.
- `scripts/windows/debug_console.ps1` - Windows 到 WSL2 Debug Console 的入口。
