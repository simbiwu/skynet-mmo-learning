# 06 - Coroutine and Concurrency

## The critical misconception

"A Skynet service is single-threaded" does **not** mean one message handler runs to completion before any other handler can change service state.

A more accurate statement is:

> One Lua state is not executing Lua instructions concurrently on two OS worker threads, but a handler can yield and another coroutine in the same service can run before the first resumes.

## Example race

```lua
local gold = player.gold
local price = skynet.call(shop, "lua", "price", item_id) -- yield
player.gold = gold - price
```

During the call, another coroutine may modify `player.gold`. When the first coroutine resumes it writes from a stale snapshot.

## Strategy used in this repository

All client business requests for one PlayerAgent enter:

```lua
local serial = require("skynet.queue")()
return serial(fn, args)
```

This deliberately recreates a property familiar from many classic MMO GameServer designs: different players can progress independently, while one player's state-changing requests are serialized.

## Do not over-lock

Do not wrap every service in one giant queue without thought. Scene commands in this lesson do not make blocking `skynet.call` calls during core AOI mutations, so they naturally finish without yield points. Understand where yield boundaries exist before adding serialization.

## Review rule

When reading or writing Skynet code, visually mark every:

- `skynet.call`
- `cluster.call`
- socket operation that waits
- `skynet.sleep`
- queue wait

Then ask: "what state did I read before this point, and can it become stale before resume?"
