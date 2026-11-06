# The hub: FunnelRadar's local API

The hub lets another program on the Mac read FunnelRadar, so Remote Code can attach later. Whoever runs the engine runs the hub: the app does, and without the app `Contents/MacOS/funnelradar-hub hub --attached` does, ending with its parent. When the app opens it asks a running hub to end and takes over.

The hub listens on 127.0.0.1 only. While it runs, `~/Library/Application Support/FunnelRadar/control.json` (mode 0600) holds `{ version, port, token, pid }`. Every request sends `Authorization: Bearer <token>`.

| Request | What it does |
|---|---|
| `GET /v1/status` | `{ api, version, state, demo, budget }`. `state` is `ready`, `setup`, `missingCLI` or `signedOut`. `budget` is `{ used, limit, pausedUntil? }` |
| `GET /v1/portfolio` | Each project, the movers and the leaks, without long series |
| `GET /v1/projects/<id>` | One project's full report |
| `GET /v1/alerts` | Recent alerts, newest first |
| `POST /v1/refresh` | `{ project? }` reads again, within the budget. A project read in the last 5 minutes is skipped |
| `POST /v1/yield` | Ends a `funnelradar-hub` so the app can take over |
| `GET /v1/events` | Server-sent events: `portfolio` (read it again) and `alert` (the alert as JSON) |

No request reads Mixpanel except `POST /v1/refresh`. Bump `Hub.api` when a change breaks a client.
