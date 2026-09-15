# 08 - Testing and Benchmark

## Run everything

Linux/WSL2:

```bash
./scripts/linux/test.sh
```

Windows PowerShell:

```powershell
.\scripts\windows\test.ps1
```

## Unit tests

`tests/unit/run.lua` runs pure Lua tests using Skynet's bundled Lua 5.4. AOI、combat 与 movement 计算都刻意保持为无 Skynet 依赖的模块，所以不用启动 Actor runtime 也能测试边界条件。

## Integration smoke test

`tests/integration/smoke.sh`:

1. launches a real Skynet node with `config/test.lua`
2. waits until `service/main.lua` reports startup complete
3. launches the real Sproto TCP client
4. logs in player 10001
5. sends ping
6. repeatedly attacks monster 100001
7. verifies the monster dies
8. 发送越界移动并验证 `OUT_OF_BOUNDS`
9. prints `INTEGRATION_SMOKE_OK`

This catches mistakes that unit tests cannot: Gate forwarding, PTYPE_CLIENT dispatch, Sproto framing, service creation, RPC response handling and network push ordering.

自动测试还会为官方 `client.socket` 保持一个无数据但不 EOF 的 stdin FIFO。该 C module 会创建 stdin 读取线程，并在非交互环境的 stdin 立即 EOF 时结束整个 client process；FIFO 只消除测试运行器与真实 terminal 的环境差异，不改变网络输入或游戏行为。shell 看到 `SMOKE_OK` 后关闭 FIFO writer，让官方 stdin pthread 收到 EOF 并结束 process。直接从主 Lua thread 调用 `os.exit` 会在 glibc 关闭仍被 `fgets` 使用的 stdin 时形成 futex 等待，因此退出协调留在测试脚本。

## AOI benchmark

```bash
./scripts/linux/benchmark_aoi.sh 10000 100000
```

Output includes query throughput, average 3x3 candidate count and allocated cell count.

Benchmark numbers are machine-specific. Use it comparatively when changing grid size/data structure; do not treat one laptop result as server capacity.
