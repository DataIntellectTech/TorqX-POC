/ tickerlogreplay1: replays stp1's logs for one date into hdbreplay; set tplogdir to that date's directory
replay:`schemafile`hdbdir`tplogdir!(`database.q;`:hdbreplay;`:tplog/stp1_2026.10.02)
