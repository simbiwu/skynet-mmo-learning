# 10 - Linux

Install prerequisites (Ubuntu/Debian example):

```bash
sudo apt update
sudo apt install -y build-essential autoconf git gdb netcat-openbsd
```

Then:

```bash
./scripts/bootstrap_skynet.sh
./scripts/linux/build.sh
./scripts/linux/test.sh
```

Run server:

```bash
./scripts/linux/run_server.sh
```

Run interactive client in another terminal:

```bash
./scripts/linux/run_client.sh
```

The server listens on 8888 and debug console on 8000 by default.

连接 Debug Console：

```bash
./scripts/linux/debug_console.sh
```

逐行调试 Lua Service 和使用 GDB 的说明见 `docs/16_DEBUGGING.md`。
