# Security

Please report vulnerabilities through [GitHub's private reporting](https://github.com/ardasnturk/funnelradar/security/advisories/new).

* FunnelRadar never handles your password or OAuth token; `mp` does, in `~/Library/Application Support/FunnelRadar/mp`.
* A service account secret stays in your Keychain and reaches `mp` through its environment, never its arguments.
* The hub listens on 127.0.0.1 and needs the token from a `0600` file.
* Cached reports stay in `~/Library/Application Support/FunnelRadar`, a `0700` folder.
* `mp` is pinned, and installed from PyPI through `uv` or `pip`.
