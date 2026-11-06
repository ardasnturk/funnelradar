# Contributing

Issues and pull requests are welcome.

* `FunnelKit` holds everything testable. Add a test with a change: `swift test --package-path FunnelKit`.
* After changing `project.yml`, run `xcodegen generate` and commit the project.
* New strings go in `scripts/l10n/source.py` with all nine languages. Then run `python3 scripts/l10n/source.py && python3 scripts/l10n.py`.
* `mp` is pinned in `ToolInstaller.version`. Moving the pin means checking every JSON shape in `MPParse` against the new source, because the CLI is a pre-release.
* A new query must go through `Engine.call`, and must not run when a view opens. Say what it costs in `docs/DECISIONS.md`.
* Never add real events, counts or project names to tests, fixtures or screenshots. Use `--demo`.
* `swift test` skips the real install unless `FUNNELRADAR_LIVE_INSTALL` names a folder (about 300 MB).
