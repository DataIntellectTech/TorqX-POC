/ tickerlogreplay1 settings - the same as tickerlogreplay1.toml; keep one. If both are present, .toml wins on any key both set.
/ tickerlogreplay1: replays stp1's logs into hdbreplay. Pick the run on the command line, e.g.
/   torqx.sh start tickerlogreplay1 -tplogdir tplog/stp1_2026.10.05 -hdbdir hdb
/ every key is set; each is overridable as -<key>
schemafile:`database.q
hdbdir:`hdbreplay
tplogdir:`
tplogfile:`                     / a single log file instead of tplogdir
segmentedmode:1b                / tplogdir is a segmented tickerplant log directory
tablelist:`all
firstmessage:0
lastmessage:0W
messagechunks:0W
partitiontype:`date
clean:1b
emptytables:1b
sortafterreplay:1b
sortcsv:`
basicmode:0b
checklogfiles:0b
gc:1b
autoreplay:1b
exitwhencomplete:1b
partandmerge:0b
tempdir:`tempmergedir
mergemethod:`part
mergenumrows:10000000
mergenumbytes:500000000
