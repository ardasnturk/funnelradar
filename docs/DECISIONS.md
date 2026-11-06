# Decisions

## D-001 — Read through the official CLI, at a pinned version
**Status:** accepted

FunnelRadar reads Mixpanel through `mp` from `mixpanel-headless`, which does the OAuth sign-in and token refresh. The CLI is a pre-release, so the version is pinned (0.4.0) and installed into FunnelRadar's own venv rather than taken from the PATH: `mp` is a short name another tool may use, and a new version may change the JSON. `MPParse` tolerates missing fields, and its tests copy the shapes documented in 0.4.0's source.

**Not verified against a real account.** Nothing has run against real data. The shapes come from the CLI's source and help text.

## D-002 — Read-only
**Status:** accepted

`mp` can create dashboards, change flags and delete things. `AnalyticsSource` only has reads, so a mistake can't touch an account.

## D-003 — A sign-in of its own
**Status:** accepted

`mp` gets `MP_STORAGE_DIR` and `MP_CONFIG_PATH` inside FunnelRadar's folder (0700), so signing out here doesn't touch an `mp` the person uses in a terminal, and the reverse. Every other `MP_*` variable is cleared first: `mp` reads `MP_PROJECT_ID` ahead of `--project`, so a stray one would silently query the wrong project.

The browser sign-in is `mp account add` then `mp account login`, not `mp login`. `mp login` asks which project on a terminal, and without one it fails after the browser step when the account sees several projects. `mp account login` doesn't ask. The region must be picked first.

A service account is never given to `mp login`, which would write the secret to its config. It stays in the Keychain, and each run gets `MP_USERNAME`, `MP_SECRET`, `MP_REGION` and `MP_PROJECT_ID` in its environment, which is how `mp` takes one without storing it. Listing projects needs some project id, and `mp` itself uses `0` for that.

## D-004 — The budget shapes the design
**Status:** accepted

The Query API allows 60 queries an hour and 5 at once, shared with the project's other integrations. A full read of one app is 13 queries: top events, event names, movers, daily users, monthly users, the funnel list, two for each of three funnels, and retention (listing bookmarks with the funnels uses the App API, not this budget).

Nearly all of that is about days that have ended, so it can't change during the day. The 2-hourly refresh therefore costs one query (today's top events), and the full read runs when the project's day changes or its events do. That turns about 13 queries every 2 hours per app into about 24 a day.

One query at a time, 5 seconds apart, at most 40 in a rolling hour, counted across restarts. Above about three apps the first read spreads over more than an hour. A 429 stops the read and waits 5 minutes, doubling to an hour, or the server's wait if longer. A manual refresh skips what was read in the last 5 minutes and doesn't repeat the full read for 6 hours. Opening a view only reads the cache.

## D-005 — Days are the project's, and today doesn't count
**Status:** accepted

`mp` dates are in the project's time zone, so "yesterday" comes from `timezone` in `mp project list`. Today is partial and would always look like a dip, so nothing is calculated from it.

## D-006 — Numbers are never added across projects
**Status:** accepted

Projects count different key events and can share people, so a total would mean nothing. The portfolio compares them as an index, 100 = each one 90 days ago, on a 7-day average.

## D-007 — Funnel periods leave out the newest week
**Status:** accepted

Someone who entered a funnel yesterday may still convert, so a period ending yesterday always looks worse than the one before and would raise a false alarm. The window of a saved funnel isn't in the data, so both 28-day periods stop 7 days before the last full day. That delays a real fall by a week. A funnel with a window over 7 days can still look slightly low.

## D-008 — Which funnels
**Status:** accepted

Each funnel costs 2 queries, so at most 3 per project are read. `mp inspect funnels` has no dates, but `mp inspect bookmarks --type funnels` has `modified`, and a saved funnel's id is its bookmark's id. The list is sorted by that, and falls back to Mixpanel's order if bookmarks can't be read.

## D-009 — Retention cells
**Status:** accepted

The CLI documents `retention[n]` as period n, with `.retention[7]` as day 7, so D1/D7/D30 are elements 1, 7 and 30, asked for with `--intervals 31`. This is the assumption most worth checking on real data: if the first element turns out to be day 1, every retention number is one day off.

A cohort too young to have reached day n stays out of that day's average, because Mixpanel can report it as 0 and that would pull the number down. Averages are weighted by cohort size.

## D-010 — Stickiness uses Mixpanel's monthly uniques
**Status:** accepted

Unique users can't be summed across days, so MAU comes from `--unit month --type unique`, which gives calendar months. Stickiness is therefore shown for full months only, never a rolling 30 days.

## D-011 — Today's percent change isn't shown
**Status:** accepted

`inspect top-events` gives a `percent_change`, documented as a fraction in one place and shown as 12.5 in another, and it compares a part of today with yesterday. Movers use `event-counts` over two full weeks instead.

## D-012 — Events with a comma
**Status:** accepted

`--events` splits on commas, with no escape. Such an event can't be queried, so it is never the key event, isn't a mover and isn't listed in Settings.

## D-013 — Forecasts stay simple
**Status:** accepted

The trend is a least-squares line through 60 days, labelled as a trend. A fancier model would look more certain than the data of a small app allows.

## D-014 — One engine, the app or the hub
**Status:** accepted

As in MRRadar: the app runs the engine and hub in process, and without it Remote Code can start `funnelradar-hub`. The app asks a running hub to yield, so two engines don't share the budget or raise an alert twice. Reports, fired alert ids and the budget are on disk, so whichever takes over carries on.

## D-015 — Rich and JSON
**Status:** accepted

`mp project list` prints through Rich, which wraps at 80 columns when not on a terminal and would break the JSON inside a long name. `COLUMNS=100000` turns that off. Rich also treats `[beta]` in a name as markup and drops it, which only changes a label.
