/ app-level defaults - the same as default.toml; keep one. If both are present, .toml wins on any key both set.

/ take connections from discovery1 and register with it
discoveryregister:1b
connectionsfromdiscovery:1b

autoreconnect:1b                / resubscribe after a tickerplant restart

/ demo pace: retry dead connections (and so resubscribe) and discovery every 10s (discovery1 keeps 0D from its builtin settings)
retry:0D00:00:10
discoveryretry:0D00:00:10

/ ms; the wait loop dials every dead peer on each poll
hopentimeout:200

/ access control, every process. Rules come from appconfig/permissions/ (app) layered on
/ kdbx-modules/di/torq/permissions/ (framework). Processes authenticate to each other with the
/ credentials in appconfig/passwords/default.txt - see kdbx-modules/di/permissions.
permissions:enlist[`enabled]!enlist 1b
