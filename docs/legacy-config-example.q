/ Legacy .q settings example - di.torq.config STILL supports .q settings files. The cascade
/ (di/config/config.q:mergetier) tries "<tier>.q" then "<tier>.toml" for every tier, so .q
/ and .toml can even coexist mid-migration; .toml wins on a key clash. This file is the .q
/ equivalent of appconfig/settings/rdb1.toml.
/
/ Format: flat `name:value` lines, one process's config, no \d namespace switches (unlike
/ legacy TorQ settings, which set several global namespaces per file). Blank lines and lines
/ starting with "/" are ignored. Symbol-shaped values take a leading backtick - TOML has no
/ symbol type, so its string values come back as q strings; consumers normalise with `$ at the
/ point of use, so the SAME module code consumes either format unchanged.

tickerplanttypes:`tickerplant
hdbtypes:`hdb
hdbdir:`hdb
replaylog:1b
tpwaittimeout:30000
reloadenabled:1b

/ --- TOML equivalent (appconfig/settings/rdb1.toml) ---
/ tickerplanttypes = "tickerplant"
/ hdbtypes         = "hdb"
/ hdbdir           = "hdb"
/ replaylog        = true
/ tpwaittimeout    = 30000
/ reloadenabled    = true
