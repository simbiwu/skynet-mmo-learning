# 04 - Login Flow

## Sequence

```text
Client TCP connect
  -> official Gate accepts fd
  -> Gate sends "socket/open" to Watchdog
  -> Watchdog records {fd, connection_id, CONNECTED}
  -> Watchdog calls Gate accept to begin reads

Client sends login request
  -> Gate has no Agent yet, so sends copied payload to Watchdog
  -> Watchdog Sproto-decodes login
  -> state = AUTHING BEFORE any skynet.call
  -> Auth.verify
  -> PlayerMgr.login
     -> sharded queue prevents duplicate PlayerAgent creation
     -> PlayerAgent.load
        -> StorageMgr -> worker -> load player
  -> PlayerAgent.bind_client
  -> PlayerAgent.enter_world
     -> SceneMgr -> Scene.enter
  -> Gate.forward(fd, 0, agent)
  -> login response is queued to socket
  -> Agent.client_ready flushes AOI snapshot pushes
```

## Why state changes happen before `call`

`skynet.call` can yield. If Watchdog leaves a connection in `CONNECTED` while waiting for Auth, another packet can be dispatched by another coroutine and execute the login path again. `AUTHING` is set first to close that window.

## Why every call is followed by `alive(fd, connection)`

While Watchdog is suspended in Auth/PlayerMgr/Agent/Scene calls, the client may disconnect and Gate may deliver `socket/close`. The old coroutine then resumes. It must not keep operating on a dead/reused fd.

## Why `connection_id` exists in addition to fd

OS socket descriptors can be reused. A delayed close/kick carrying fd 100 must not affect a later connection that also happens to receive fd 100. `connection_id` acts as a generation number, analogous to validating both an object handle and its unique identity/version.
