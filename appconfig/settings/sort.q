/ sort proctype settings (sort1) - the same as sort.toml; keep one. If both are present, .toml wins on any key both set.
/ It inherits savedir, hdbdir and the reload settings from wdb.q through -parentproctype wdb; di.torq's
/ builtin sort settings set mode `sort.
workers:2                       / sort with -s -2, spreading the per-table sorts over sortworker1 and sortworker2
