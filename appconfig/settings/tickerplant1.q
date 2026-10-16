/ tickerplant1 settings - the same as tickerplant1.toml; keep one. If both are present, .toml wins on any key both set.
/ Schema comes from the app's database.q (di.torq.proc.tickerplant's default schemafile). eodtime
/ rolls at GMT midnight by default (rolltimezone / datatimezone / rolltimeoffset omitted).

publishmode:`immediate          / or `batched (buffer per table, flush every pubperiod seconds)
tplogdir:`tplog                 / relative to TORQXAPPHOME; a per-date log tp<date> is kept here
