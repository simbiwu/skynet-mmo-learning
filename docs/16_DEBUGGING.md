# 16 - 调试环境

## 三层调试方式

这个工程提供三种互补的调试入口：

- VS Code + LuaPanda：在个人开发环境中对指定 Lua Service 使用图形断点、条件断点、Call Stack、Variables、Watch 和单步执行。
- Skynet `Debug Console`：查看 Service、Mailbox、Coroutine、内存和网络状态，也能进入指定 Lua Service 后逐行执行。它理解 Skynet 的消息和 Coroutine，是运行时诊断基线。
- VS Code + GDB：调试 Skynet Runtime、C Service 和 Lua C module。Lua 业务断点不要误用 GDB 代替。

LuaPanda 只在 `config/debug_luapanda.lua` 下加载，并且一次只注入显式选择的一个 Service。正常服务器使用 `config/game.lua`，测试使用 `config/test.lua`，两者都不会加载 LuaPanda、LuaSocket 或额外 Debug Hook。

固定依赖是 LuaPanda 3.3.1 commit `e3ac3d3314f24cf939c36cac5b7dc1f2ed6ee129`、LuaSocket v3.1.0，以及 Skynet 官方 v1.8.0 Bundled Modified Lua 5.4.7。这里没有自行实现 Debug Adapter，也没有切换到调试器专用的 Skynet Fork。

## 一次性准备

Windows 用户应先完整执行 `docs/09_WINDOWS_WSL2.md`。该文档从安装 Ubuntu、首次创建用户、打开 terminal、定位 `G:` 盘工程，一直说明到用 `code .` 打开 WSL 工作区；如果尚未看到 `WSL: Ubuntu`，先不要继续本章。

Ubuntu/Debian 所需工具为：

```bash
sudo apt update
sudo apt install -y build-essential autoconf git gdb netcat-openbsd
```

`rlwrap` 是可选项，安装后 `Debug Console` 会有命令历史：

```bash
sudo apt install -y rlwrap
```

VS Code 会推荐 Remote - WSL、C/C++、Lua Language Server 和 LuaPanda。工作区已固定 Lua Language Server 为 Lua 5.4，并加入项目与 Skynet 的 `lualib` 搜索路径。LuaPanda 自带的旧代码检查已通过工作区设置关闭，避免与 Lua Language Server 重复报诊断；LuaPanda 只负责 Debug Adapter。

确认扩展安装在 WSL 侧，而不只是 Windows Local 侧：

1. VS Code 左下角必须显示 `WSL: Ubuntu`；
2. 打开 Extensions，搜索 `LuaPanda`；
3. 扩展详情应显示 `Extension is enabled on WSL: Ubuntu`。

如果扩展只出现在 Windows Local 而没有安装到 WSL，请在 VS Code 的 WSL Terminal 中执行：

```bash
code --install-extension stuartwang.luapanda
```

不要从普通 Windows PowerShell 用 `code --remote ... --install-extension` 判断安装位置；以 WSL Terminal 中 `code --list-extensions --show-versions` 的结果，以及 `~/.vscode-server/extensions/stuartwang.luapanda-3.3.1` 是否存在为准。

## 一次性准备 LuaPanda Runtime

在 WSL Workspace 中运行 task `Skynet MMO：准备 LuaPanda 调试环境`，等价命令是：

```bash
./scripts/linux/build_luapanda.sh
```

脚本依次完成：

1. 从 Tencent/LuaPanda 拉取固定 commit；
2. 从 lunarmodules/luasocket 拉取 v3.1.0；
3. 使用 `third_party/skynet/3rd/lua/lua.h` 编译 LuaSocket；
4. 把 LuaPanda 唯一需要的 `socket/core.so` 放到 `third_party/luapanda-runtime/luaclib`；
5. 使用 Skynet 自带的 Lua 解释器执行 `require "socket.core"` 验证 ABI 和加载路径。

成功标志是：

```text
LUAPANDA_RUNTIME_OK
```

这里不能直接安装 Ubuntu 的 `lua-socket` 包：它针对 System Lua 构建，而本工程必须使用 Skynet Bundled Lua 5.4.7。即使 Lua 版本号相同，也不应隐式混用 Header、Module Path 和 ABI。

脚本也不调用 LuaSocket 上游的 `make install`。该目标会执行 `chmod`，而 `/mnt/g` 等 DrvFs Mount 可能拒绝这一操作；项目只复制 LuaPanda 实际需要的 `socket.core`，不吞掉错误，也不修改上游源码。

## 第一次使用 VS Code 图形断点

### 调试 Scene

1. 确认普通服务器没有占用 `8888` 端口；
2. 打开 `service/scene/scene.lua`；
3. 在 `CMD.move` 或 `CMD.attack` 的可执行语句左侧设置红点；
4. 按 `F5`，选择 `Skynet Lua：LuaPanda 调试 Scene`；
5. 等服务器输出 `[Main] startup complete`；
6. 另开 VS Code Terminal，运行 task `Skynet MMO：启动交互客户端`；
7. 登录后输入 `move 101 100` 或 `attack 100001`；
8. 命中后检查 Call Stack、Variables、Watch，并使用 `F10`、`F11`、`Shift+F11` 和 `F5`。

`scene/scene` 在服务器启动阶段创建，所以 LuaPanda 会较早连接。不要把断点设置在注释、空行或只在 `require` 时执行一次而已经错过的代码上。

客户端命令必须输入到名称为 `Skynet MMO：启动交互客户端` 的 Task Terminal，并确认其中出现 `Commands: ping | move X Y | attack ID | logout`。`Run Program File (LuaPanda)` 是服务器 Terminal，不处理客户端命令。

交互客户端使用 `client.socket` 的 `socket.readstdin()`。该 C 模块加载时已经创建 stdin pthread，由它读取 TTY 并把完整行送入私有队列；Lua 主循环只能消费这个队列，不能同时调用 `io.read`。否则两个 Reader 会竞争同一 stdin，典型现象就是 Terminal 回显了 `move`，但没有 `[Response]`，Scene 断点也不触发。

### 调试 PlayerAgent

1. 在 `service/player/player_agent.lua` 的业务命令中设置断点；
2. 按 `F5`，选择 `Skynet Lua：LuaPanda 调试 PlayerAgent`；
3. 服务器启动后运行交互客户端；
4. PlayerAgent 在登录过程中动态创建，此时它才会加载 LuaPanda 并连接 VS Code；
5. 发送 `ping`、`move` 或 `attack` 触发断点。

如果没有客户端登录，PlayerAgent 不存在，VS Code 等待连接是正常状态。

### 调试其他 Service

复制 `.vscode/launch.json` 中任一 LuaPanda Configuration，只修改名称和 `args` 的第一个参数：

```json
"args": ["gateway/watchdog", "8818"]
```

该字符串必须与 `skynet.newservice` / `skynet.uniqueservice` 使用的 Service Name 完全一致。一次只选择一个目标 Service；如果同名 Service 会创建多个实例，多个 Lua State 会争抢同一个 LuaPanda Port。此时应先用固定测试场景保证只创建一个实例，而不是把 Debugger 注入整个进程。

## 接入链路

按 `F5` 后的实际链路是：

```text
Windows VS Code UI
  -> WSL 中的 LuaPanda Debug Adapter 监听 127.0.0.1:8818
  -> run_luapanda_server.sh 设置目标 Service/Host/Port
  -> skynet config/debug_luapanda.lua
  -> lualib/debug/luapanda_preload.lua
  -> 先用 skynet.core 读取目标 Service，不能提前 require("skynet")
  -> 只有 SERVICE_NAME 匹配时先 require("LuaPanda") 并安装 Coroutine Hook
  -> LuaPanda 完成包装后再 require("skynet")
  -> LuaPanda 通过 socket.core 连接 Adapter
  -> Debug Hook 管理断点和 Coroutine 单步
```

`.vscode/launch.json` 设置 `useCHook=false`，明确使用 Lua Debug Hook。LuaPanda 发布包中的 `libpdebug` 并不是为本工程的 Linux + Bundled Modified Lua 5.4.7 ABI 构建，不能为了提速直接加载未知二进制。

### 自己接入 LuaPanda 时必须遵守的加载顺序

这不是 Skynet 的普通配置细节，而是 Debug Hook 能否覆盖业务 Coroutine 的必要条件。

`third_party/skynet/lualib/skynet.lua` 在模块顶层执行类似下面的缓存：

```lua
local coroutine_create = coroutine.create
```

此后，Skynet 用这个局部函数创建消息分发 Coroutine。LuaPanda 加载时会包装全局的 `coroutine.create`，以跟踪新 Coroutine 并安装 Debug Hook。因此顺序必须是：

```text
读取调试配置（只 require "skynet.core"）
  -> 判断当前 SERVICE_NAME 是否为目标
  -> require "LuaPanda" 并 start
  -> require "skynet"
  -> 进入 Service 业务代码
```

不能写成下面这样：

```lua
local skynet = require "skynet" -- 错：此时已经缓存原始 coroutine.create
require("LuaPanda").start(host, port)
```

这种错误很隐蔽：Debug Adapter 能连接，VS Code 也会把断点标记为已验证；模块顶层代码甚至可能命中。但 Skynet 随后创建的消息分发 Coroutine 没有进入 LuaPanda 的 Coroutine Pool，所以 `move`、`attack` 等业务消息不会命中断点。

在其他 Lua Runtime、Coroutine Scheduler 或 Actor Framework 中自行接入时，也按下面的顺序检查：

1. 搜索 Runtime 是否在模块加载期缓存 `coroutine.create`、`coroutine.resume`、`debug.sethook`；
2. 确认 Debugger 的 Coroutine 包装发生在 Runtime 首次加载之前；
3. 不要仅以“Adapter 已连接”或“断点已验证”作为验收；
4. 必须触发一条由 Runtime 新建 Coroutine 处理的真实业务消息，并命中断点；
5. 同时验证未选择的 Service、正常配置和测试配置不会加载 LuaPanda。

项目用 `tests/tooling/test_luapanda_preload_order.lua` 固化了这条约束。运行完整测试时，它会模拟 LuaPanda 包装和 Skynet 模块加载，并断言 Skynet 缓存的是包装后的 `coroutine.create`。

## LuaPanda 对 Skynet 调度的影响

LuaPanda 是成熟工具，但 Debugger 不会让并发语义消失：

- 一个 `snlua` Service 对应独立 Lua State；
- 断点暂停的是命中的 Coroutine，不是整个 Skynet Process；
- 同一 Service 的其他 Coroutine 仍可能运行；
- `skynet.call` 前读取的状态，在单步跨过 yield 后仍可能陈旧；
- LuaPanda 使用标准 LuaSocket，调试通信可能短时阻塞执行该 Service 的 Worker Thread；
- Debug Hook 会显著改变时序和性能，不能用来做 Benchmark 或复现所有 Race Condition。

因此 LuaPanda 只用于个人、隔离的开发环境。共享联调优先用 Trace、状态快照和 Debug Console；生产配置禁止加载它。

## 最短调试流程

1. 运行任务 `Skynet MMO：拉取 v1.8.0`。
2. 运行任务 `Skynet MMO：构建`。
3. 运行任务 `Skynet MMO：启动服务器`。
4. 运行任务 `Skynet MMO：连接 Debug Console`。
5. 另开终端运行 `Skynet MMO：启动交互客户端`。

也可以直接使用命令：

```bash
./scripts/linux/run_server.sh
./scripts/linux/debug_console.sh
./scripts/linux/run_client.sh
```

Windows PowerShell 对应：

```powershell
.\scripts\windows\run_server.ps1
.\scripts\windows\debug_console.ps1
.\scripts\windows\run_client.ps1
```

`config/game.lua` 默认只在 `127.0.0.1:8000` 开启 `Debug Console`。`config/test.lua` 将端口设为 `0`，自动测试不会暴露调试端口。生产环境必须关闭它，因为 `call`、`inject`、`kill` 等命令拥有完全控制能力。

## Debug Console 常用命令

连接后先输入：

```text
help
list
service
stat
mem
netstat
```

- `list`：列出所有 Service 与启动参数，可找到动态创建的 `PlayerAgent`、`Scene` 地址。
- `service`：列出 `uniqueservice`。
- `stat`：查看每个 Service 的 CPU、消息数和 mailbox 长度。
- `task :地址`：查看该 Service 当前 Coroutine；排查卡住的 `skynet.call` 时很有用。
- `info :地址`：查看 Service 调试信息。
- `trace :地址 lua on`：打开 Lua 协议消息 trace；排查完用 `trace :地址 lua off` 关闭。
- `call :地址 "stats"`：调用本项目 `Scene.CMD.stats`。这是同步 RPC，会让 Console 等待返回。

地址以实际 `list` 输出为准，例如 `:0100000c`，不要把文档示例写死到脚本中。

## 逐行调试 Lua Service

先从 `list` 找到目标地址，然后：

```text
debug :0100000c
watch("lua")
```

`watch("lua")` 会等待目标 Service 的下一条 Lua 协议消息。此时从客户端发送 `move` 或 `attack`，Console 会停在对应 dispatch 路径。停住后可用：

```text
n                 单步越过函数调用
s                 单步进入函数调用
player            求值并打印当前变量
c                 继续当前 Coroutine
cont              退出该 Service 的调试模式
```

调试期间目标 Service 可能暂停，但其他 Actor 仍会运行。于是断点前读取的状态，在跨 `skynet.call` 或其他 yield 后仍可能过期；调试工具不会替你消除竞态。不要在公开服务器上长时间停住 `Scene` 或 `PlayerAgent`。

## GDB 调试 Skynet Runtime

在 WSL/Linux 工作区打开 VS Code 的“运行和调试”，选择：

```text
Skynet Runtime：GDB 启动服务器（WSL/Linux）
```

它会先执行构建，再以 `config/game.lua` 启动 `third_party/skynet/skynet`。可在 `third_party/skynet/skynet-src`、`service-src` 或 `lualib-src` 下设置 C 断点。

此配置只支持 WSL/Linux 工作区。若从普通 Windows 窗口直接启动，`/usr/bin/gdb` 与 Linux ELF 路径不在同一环境；请先用 Remote - WSL 重新打开仓库。

## 常见失败

- VS Code 没有 LuaPanda Configuration：确认安装的是 `stuartwang.luapanda`，并安装在 WSL 侧。
- `module 'LuaPanda' not found`：运行 `Skynet MMO：准备 LuaPanda 调试环境`，不要手工复制不明版本的脚本。
- `module 'socket.core' not found`：重新运行准备任务并确认出现 `LUAPANDA_RUNTIME_OK`。
- 红点是灰色：确认使用的是 LuaPanda Configuration，不是 GDB；确认目标 Service Name 和源码路径大小写正确。
- 断点显示已验证、Adapter 日志也显示连接成功，但 `move` 等消息处理断点不命中：首先检查是否在 `require("LuaPanda")` 之前加载了 `skynet`。连接成功只证明 Socket 和路径映射正常，不证明新建的消息 Coroutine 已安装 Hook。
- 客户端 Terminal 已显示命令提示，输入 `move` 后只有本地回显、没有 `[Response]`：确认客户端使用 `socket.readstdin()`，不要让 `io.read` 与 `client.socket` 内部 stdin pthread 竞争同一个 TTY。项目由 `tests/tooling/test_client_stdin.lua` 固化此约束。
- `Address already in use`：停止旧的 LuaPanda Session，或者同时修改 `args` 中端口和 `connectionPort`。
- Scene 可以命中而 PlayerAgent 一直等待：先启动客户端完成登录，PlayerAgent 是动态创建的。
- 断点位置与当前行轻微偏移：确认 `useCHook=false`；不要加载 LuaPanda 自带的预编译 C Hook。
- F5 后游戏端口绑定失败：普通服务器仍在运行，先在其 Terminal 使用 `Ctrl+C` 停止。
- 找不到 `third_party/skynet/skynet`：先运行拉取和构建任务。
- `缺少 nc`：安装 `netcat-openbsd`。
- 连接 `8000` 被拒绝：确认服务器使用 `config/game.lua`，并等待日志出现 `startup complete`。
- Lua Language Server 报 Skynet module 不存在：确认已经拉取 `third_party/skynet`，然后执行 `Lua: Restart Language Server`。
- GDB 断点是灰色：确认 C/C++ extension 安装在 WSL 侧，并确认构建产物含调试符号。

## 上游资料

- LuaPanda 仓库与特性：<https://github.com/Tencent/LuaPanda>
- LuaPanda 接入说明：<https://github.com/Tencent/LuaPanda/blob/master/Docs/Manual/access-guidelines.md>
- LuaPanda FAQ：<https://github.com/Tencent/LuaPanda/blob/master/Docs/Manual/FAQ.md>
- LuaSocket v3.1.0：<https://github.com/lunarmodules/luasocket/releases/tag/v3.1.0>
- Skynet 官方 Coroutine Debugger 原理：<https://blog.codingnow.com/2015/02/skynet_debugger.html>
