/ app-wide .servers settings - .q because TOML has no timespan type
/ register with discovery1 and take connection details from it
discoveryregister:1b
connectionsfromdiscovery:1b
/ demo pace: retry dead connections and discovery every 10s. discovery1 keeps 0D from its builtin settings
retry:0D00:00:10
discoveryretry:0D00:00:10
/ 200ms: the wait loop dials every dead peer on each poll
hopentimeout:200
