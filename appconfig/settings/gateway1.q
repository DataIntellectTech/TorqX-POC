/ gateway1 settings - the same as gateway1.toml; keep one. If both are present, .toml wins on any key both set.
/ The query front end: connects to the rdb + hdb, and routes a client query across them, joining the
/ results. A client does
/   h:hopen`::5306; neg[h](`.gw.asyncexec;"select from trade";`rdb`hdb); h[]
/ and gets the rdb's in-memory (today) trades razed with the hdb's on-disk (historical) trades.
/ Also gates queries during the wdb's EOD reload. See kdbx-modules/di/torq/proc/gateway.

backendtypes:`rdb`hdb`idb       / proctype(s) to connect to and route queries across
/ synccallsallowed omitted -> 0b (deferred-sync / async only)
/ errorprefix omitted -> "error: "

/ check a client's query before dispatching it, and run it on each backend as that client
/ rather than as the gateway - so the data processes remain the enforcement point
permissioned:1b
