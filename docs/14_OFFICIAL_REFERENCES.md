# 14 - Official References

Pinned learning baseline:

- Skynet repository: https://github.com/cloudwu/skynet
- v1.8.0 tag: https://github.com/cloudwu/skynet/tree/v1.8.0
- v1.8.0 README: https://github.com/cloudwu/skynet/blob/v1.8.0/README.md
- Official example Gate: https://github.com/cloudwu/skynet/blob/v1.8.0/service/gate.lua
- Official example Watchdog: https://github.com/cloudwu/skynet/blob/v1.8.0/examples/watchdog.lua
- Official example Agent: https://github.com/cloudwu/skynet/blob/v1.8.0/examples/agent.lua
- Official example Client: https://github.com/cloudwu/skynet/blob/v1.8.0/examples/client.lua
- Official Debug Console: https://github.com/cloudwu/skynet/blob/v1.8.0/service/debug_console.lua
- Official remote Lua debugger: https://github.com/cloudwu/skynet/blob/v1.8.0/lualib/skynet/remotedebug.lua
- Official Wiki: https://github.com/cloudwu/skynet/wiki

仅用于开发环境的图形化 Lua 调试：

- Tencent LuaPanda: https://github.com/Tencent/LuaPanda
- LuaPanda integration guide: https://github.com/Tencent/LuaPanda/blob/master/Docs/Manual/access-guidelines.md
- LuaSocket v3.1.0: https://github.com/lunarmodules/luasocket/releases/tag/v3.1.0

LuaPanda 和 LuaSocket 是开发工具依赖，不是 Skynet 官方组件。正常、测试和生产启动路径不会加载它们。

When Codex or another AI gives an answer about an exact Skynet API, prefer verifying behavior against the pinned source rather than relying on memory or a tutorial written for an older Skynet/Lua version.
