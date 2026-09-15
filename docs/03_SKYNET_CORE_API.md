# 03 - Skynet Core API Used Here

## `skynet.start(fn)`

Registers/runs the initialization body of a Lua service. Every service file in this repository ends in a `skynet.start` block. Think of it as the Actor's initialization entry rather than a C/C++ process `main()`.

## `skynet.newservice(name, ...)`

Creates a new Lua service. Each call creates another service instance. This project uses it for PlayerAgent, Scene and storage workers.

Example from `player_mgr.lua`:

```lua
local agent = skynet.newservice("player/player_agent")
```

## `skynet.uniqueservice(name, ...)`

Returns/creates one unique service of that name inside the current Skynet node. `main.lua` uses it for managers/config/auth/watchdog.

## `skynet.dispatch("lua", callback)`

Registers the handler for the built-in Lua message protocol. Callback arguments are conceptually:

```text
session, source, command, ...
```

- `session`: non-zero for a `call` that expects a response; zero for `send`.
- `source`: service address of the sender.
- `command`: our application-level command string.

## `skynet.call(address, "lua", command, ...)`

Sends a request and suspends the current coroutine until a response arrives. Treat every call as a potential yield/re-entry boundary.

Do not mentally translate it to a normal C++ virtual function call. A better model is:

```text
serialize message -> mailbox -> target coroutine -> response -> resume caller
```

## `skynet.send(address, "lua", command, ...)`

Fire-and-forget message. No response is awaited. Used for notifications such as Scene -> PlayerAgent pushes.

## `skynet.retpack(...)`

Packs values and returns them to a caller waiting in `skynet.call`. A service handling a `send` normally must not return an RPC response.

## `skynet.self()`

Returns the current service address. Scene stores a PlayerAgent address so it can later send AOI events to that player.

## `skynet.queue()`

Creates a coroutine serialization queue/critical section. This repository uses it for:

- PlayerMgr login creation races.
- PlayerAgent business request serialization.
- SceneMgr scene creation race.

It is not a pthread mutex; it coordinates Skynet coroutines.

## `skynet.timeout(ticks, fn)`

Schedules a callback. Skynet uses 100 ticks per second, so 500 = 5 s and 6000 = 60 s.

Used here for reconnect grace period, Scene tick and monster respawn.

## `skynet.now()`

返回 Skynet 启动后的当前 tick，1 秒为 100 ticks。权威移动用它计算两次请求间应补充多少 Token Bucket 额度。它只读取时钟，不会 yield；因此 `Scene` 可以在同一段无 yield 的处理内完成“读坐标、校验、扣额度、提交坐标”。

## `skynet.register_protocol`

PlayerAgent registers `PTYPE_CLIENT`, matching official Gate's `skynet.redirect(..., "client", fd, msg, sz)`. `unpack` turns raw Sproto bytes into logical protocol values; `dispatch` handles them.

## `skynet.ignoreret()`

Gate deliberately uses the socket fd as the redirected Skynet message session. That value is not an RPC session awaiting `skynet.ret`, so PlayerAgent calls `ignoreret` exactly as the official example Agent does.
