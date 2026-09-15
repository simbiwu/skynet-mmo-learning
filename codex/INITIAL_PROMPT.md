Read AGENTS.md and docs/00_READ_ME_FIRST.md through docs/06_COROUTINE_AND_CONCURRENCY.md before proposing changes. Then audit the repository as a Skynet/MMO learning project.

Do not immediately refactor or write code. First return:
1. The complete login -> PlayerAgent -> Scene -> client-response call/message path, naming every file involved.
2. State ownership of Watchdog, PlayerMgr, PlayerAgent and Scene.
3. Every important yield point and the race/re-entry risk around it.
4. Why gate.forward changes the post-login packet path.
5. How the current 3x3 AOI works and the condition that makes 3x3 sufficient.
6. The top 5 gaps between this teaching project and a production MMO, without trying to fix all of them at once.

When referencing code, include exact file paths and relevant functions.
