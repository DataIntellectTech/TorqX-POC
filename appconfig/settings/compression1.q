/ compression1 settings - the same as compression1.toml; keep one. If both are present, .toml wins on any key both set.
/ A one-shot batch job: it compresses the hdb once and exits, so its process.csv row has no port
/ and startwithall=0 - a stack start must not rewrite the hdb.
/ Run it on demand:   torqx.sh start compression1
/ See kdbx-modules/di/torq/proc/compression.

csvpath:`:appconfig/compressionconfig.csv   / which table/column gets which algorithm
hdbpath:`:hdb                               / hdb root, under TORQXDATAHOME
/ maxage omitted -> 30, the framework default, as TorQ's own settings file ships
exitonfinish:1b                             / terminate when the pass completes
