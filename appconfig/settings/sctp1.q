/ sctp1 settings - the same as sctp1.toml; keep one. If both are present, .toml wins on any key both set.
/ sctp1: chained off stp1; rdb1 replays stp1's logs
sctpchainedtp:1b
sctploggingmode:`parent
sctptickerplantname:`stp1
sctpsubscribeto:`               / all tables
sctpsubscribesyms:`             / all syms
sctpreplay:0b
sctpschema:1b
createlogs:0b                   / logging is set by sctploggingmode
connections:enlist`segmentedtp
