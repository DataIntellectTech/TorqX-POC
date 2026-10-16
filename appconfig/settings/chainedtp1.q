/ chainedtp1 settings - the same as chainedtp1.toml; keep one. If both are present, .toml wins on any key both set.
/ chainedtp1: chained off tickerplant1; logs what it receives so rdb1 can replay it on connect
tickerplantname:`tickerplant1
pubinterval:0D00:00:01          / batching interval; 0D00:00:00 publishes immediately
tpconnsleep:10                  / seconds between attempts to connect to tickerplant1
tpcheckcycles:0W                / wait for tickerplant1 indefinitely
createlogfile:1b
logdir:`:tplog                  / relative to TORQXAPPHOME, where torqx.sh starts processes
clearlogonsubscription:0b
subscribeto:`                   / all tables
subscribesyms:`                 / all syms
replay:0b
schema:1b
connections:enlist`tickerplant
