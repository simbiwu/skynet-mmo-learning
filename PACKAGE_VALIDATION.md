# Package validation

Validation performed when this teaching package was generated:

- All project `.lua` files were parsed successfully with an available Lua-family parser/runtime (`loadfile` syntax validation).
- Pure Lua unit tests for AOI Grid and combat math passed.
- AOI benchmark executed successfully in the generation environment.
- Every Bash script passed `bash -n` syntax validation.
- VS Code JSON files parsed successfully.

Full Skynet compilation and end-to-end network smoke execution were not run in the generation sandbox because outbound Git access is disabled there and the official Skynet dependency is intentionally fetched from its pinned upstream tag by `scripts/bootstrap_skynet.sh`.

On the target machine, `./scripts/linux/test.sh` first builds Skynet if needed and then runs the real network integration test. Treat that command as the acceptance test after extraction.

## 2026-09-11 本机验收

- Windows 11 + WSL2 + Ubuntu 26.04 LTS 环境安装完成。
- 官方 Skynet `v1.8.0`（commit `ba64be6f9fa044933c77de1317f466afbade8eaa`）及 jemalloc submodule 校验完成。
- Skynet Runtime、bundled Lua 5.4.7、C Service 和 Sproto module 构建成功。
- `./scripts/linux/test.sh` 全部通过：AOI、combat、movement 单元测试，以及真实 Gate/Sproto network smoke test。
- 开发服务器 `8888` 与本机 Debug Console `127.0.0.1:8000` 启动和连接验证成功。
- 修复非交互测试环境下官方 `client.socket` stdin pthread 的 EOF/退出生命周期回归。

## 2026-09-12 LuaPanda 调试环境验收

- WSL Extension Host 已安装 `stuartwang.luapanda@3.3.1`，并确认 `debugAdapter.js` 位于 Ubuntu 的 `~/.vscode-server/extensions`。
- Tencent LuaPanda 固定在 commit `e3ac3d3314f24cf939c36cac5b7dc1f2ed6ee129`，LuaSocket 固定在 `v3.1.0`。
- LuaSocket 使用 Skynet Bundled Lua 5.4.7 Header 构建；`tests/tooling/test_luapanda_runtime.sh` 验证 `socket.core` 能由同一 Lua Runtime 加载。
- `config/debug_luapanda.lua` 启动成功，并确认只有目标 `scene/scene` 输出 `[LuaPanda]` 注入日志；Gate `8888`、Debug Console `8000` 和完整启动链正常。
- LuaPanda Debug Session 结束后未遗留 `8888`/`8000` 监听进程。
- `./scripts/linux/test.sh` 全部通过，证明正常和测试配置没有加载或依赖 LuaPanda。
- 在 `/mnt/g` 发现 LuaSocket 上游 `make install` 的 `chmod` 失败后，改为只复制实际需要的 `socket.core`，并增加 Runtime 布局/ABI 回归测试。
- 修复 Windows PowerShell 5.1 直接向 `wslpath` 传递 `G:\...` 时反斜杠丢失的问题；全部 Windows Wrapper 改用 `G:/...` 中间形式，`test_windows_wslpath.ps1` 已通过。
- 当时自动验收已覆盖 Adapter 安装、Runtime 依赖、目标 Service 注入和原有回归测试；图形断点的最终交互验收见 2026-09-15 记录。

## 2026-09-15 LuaPanda Coroutine Hook 回归修复

- 从 LuaPanda Adapter 日志确认 Debug Target 已连接，`service/scene/scene.lua:184` 断点路径已验证并成功下发，排除了 VS Code、Socket 和路径映射问题。
- 定位到 `skynet.lua` 在 LuaPanda 加载前缓存原始 `coroutine.create`，导致后续消息分发 Coroutine 没有安装 Debug Hook。
- `luapanda_preload.lua` 改为先通过 `skynet.core` 读取配置、加载 LuaPanda，再加载 `skynet.lua`；正常、测试和非目标 Service 的启动路径不变。
- 新增 `tests/tooling/test_luapanda_preload_order.lua`，断言 Skynet 缓存的是 LuaPanda 包装后的 `coroutine.create`。
- `./scripts/linux/test.sh` 全部通过：3 组单元测试、LuaPanda 加载顺序回归测试和真实 Gate/Sproto network smoke test。
- 使用当前 VS Code Debug Session，通过 Skynet Debug Console 向 `:00000012 scene/scene` 发送 `move(10001, 103, 100)`；LuaPanda 收到 `stopOnBreakpoint`，命中 `service/scene/scene.lua:184`。
- 已核对 Call Stack 为 `scene.lua:184 -> scene.lua:333 -> skynet.lua:402`，Variables 为 `player_id=10001, x=103, y=100`；用户窗口确认已跳转到断点，图形调试端到端验收完成。
- 后续在 VS Code Task Terminal 复现“输入有回显但无 Response”：`client.socket` 的 stdin pthread 与客户端 `io.read` 同时读取同一个 TTY，命令被 C 线程取走后 Lua 主循环永久等待。
- 交互客户端改用 Skynet 官方 `socket.readstdin()` 队列，并新增 `tests/tooling/test_client_stdin.lua`，禁止重新引入双 stdin Reader。
- 使用修复后的客户端 PTY 登录 player `10002` 并输入 `move 109 100`；客户端成功发送 RPC，LuaPanda 再次命中 `scene.lua:184`，Variables 为 `player_id=10002, x=109, y=100`。
