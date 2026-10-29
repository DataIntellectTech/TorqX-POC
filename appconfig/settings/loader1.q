/ loader1 settings - the same as loader1.toml; keep one. If both are present, .toml wins on any key both set.
landingdir:`:data/landing
headers:`time`sym`price`size`stop`cond`ex`side
types:"PSFIBCCS"
separator:","
tablename:`trade
dbdir:`:hdb
connections:enlist`hdb
