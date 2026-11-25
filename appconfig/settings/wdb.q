/ wdb proctype settings - the same as wdb.toml; keep one. If both are present, .toml wins on any key both set.
/ Shared through -parentproctype wdb by sort1 and the sortworkers (process.csv extras), as in the FSP.
/ di.torq's builtin sort and sortworker settings beat this tier, so they keep mode `sort and the
/ sortworkers connect to nothing. See kdbx-modules/di/torq/proc/wdb.
mode:`save                      / wdb1 saves and hands end of day to sort1 (sorttypes); the FSP layout
hdbtypes:`hdb                   / proctype(s) to move partitions to / reload at EOD
rdbtypes:`rdb                   / proctype(s) to reload[date] at EOD (drop their prior day)
savedir:`wdb                    / wdb working-data root (relative to TORQXDATAHOME)
hdbdir:`hdb                     / HDB root to move sorted partitions into
reloadorder:`hdb`rdb`idb        / reload the hdb first (new partition), then the rdb (drop prior day), then the idb
