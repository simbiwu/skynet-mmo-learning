# 02 - Directory and File Map

## Root

- `README.md` - quick start and project scope.
- `AGENTS.md` - repository instructions for Codex.
- `Makefile` - Linux/WSL convenience targets.
- `compose.mysql.yml` - optional MySQL 8.4 development container.

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
- `tests/tooling/test_windows_wslpath.ps1` - 防止 PowerShell 5.1 向 `wslpath` 传递反斜杠路径时发生转义回归。

## scripts

- `scripts/bootstrap_skynet.sh` - fetches pinned v1.8.0 recursively.
- `scripts/bootstrap_luapanda.sh` - 拉取固定的 LuaPanda 3.3.1 与 LuaSocket v3.1.0。
- `scripts/linux/*` - build/run/test/benchmark.
- `scripts/linux/build_luapanda.sh` - 针对 Skynet Bundled Lua Header 构建 `socket.core`。
- `scripts/linux/run_luapanda_server.sh` - 设置单一目标 Service 并启动 Dev-only Debug 配置。
- `scripts/linux/debug_console.sh` - 通过 `nc` 连接 Skynet Debug Console。
- `scripts/windows/*` - PowerShell wrappers that execute the Linux scripts through WSL2.
- `scripts/windows/debug_console.ps1` - Windows 到 WSL2 Debug Console 的入口。
