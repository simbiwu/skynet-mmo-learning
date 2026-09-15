`./scripts/bootstrap_skynet.sh` downloads the pinned official Skynet v1.8.0 source into `third_party/skynet/`.
The dependency is intentionally not copied into this learning package so the exact upstream repository/tag remains explicit and updateable.

`./scripts/linux/build_luapanda.sh` additionally prepares development-only Lua debugging dependencies:

- Tencent LuaPanda 3.3.1, pinned to commit `e3ac3d3314f24cf939c36cac5b7dc1f2ed6ee129`, under `third_party/luapanda/`;
- LuaSocket v3.1.0 under `third_party/luasocket/`;
- the required `socket.core` C Module compiled against Skynet's bundled Lua headers under `third_party/luapanda-runtime/`.

These directories are reproducible third-party outputs and are intentionally excluded from the learning package manifest. Normal server and test configurations do not load them.
