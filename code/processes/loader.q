/ custom process type - NOT a di.* module, just a plain file dropped into
/ code/processes/, FSP-style. di.torq loads this file directly and calls
/ .loader.init[config;deps] using the same convention as built-in modules.

\d .loader

/ normalizes to a symbol whether the settings value came from a .q file (already
/ a symbol, e.g. dbdir:`:hdb) or a .toml one (di.util.toml gives plain q strings, since
/ TOML has no symbol type). 
assym:{[x] $[11h=abs type x;x;`$x]}

/ same reasoning as assym, the other direction: `string` is NOT idempotent on an
/ already-string input either (it throws 'type - a plain q string is a char list,
/ not the atom `string` expects). Used purely for log-message formatting below,
/ where a value might be a symbol (.q settings) or already a string (.toml ones).
asstring:{[x] $[10h=abs type x;x;string x]}

init:{[config;deps]
  logdep::deps`log;
  cfg::config;
  alldeps::deps;
  logdep[`info][`loader;"loader initialised, landing dir ",asstring cfg`landingdir];
  }

/ one-shot load: reads every csv in the landing dir and splays it into the target hdb,
/ partitioned by date, via the standard .Q.dpft idiom.
/ NOTE: originally called di.dataloader.loadallfiles here (per the plan), but that
/ module has a reproducible bug - dataloader.q's internal `loaddata` references a bare
/ `filesread` variable that is never correctly bound to the module-local state
/ `loadallfiles` sets up (`.z.m.filesread`), so every call throws a 'type error deep
/ inside .Q.fsn. Confirmed by calling di.dataloader directly, isolated from this POC's
/ own code. Worked around here with a minimal in-house loader instead of patching
/ someone else's in-review module; worth reporting upstream separately.
loadall:{[]
  logdep[`info][`loader;"starting load from ",(asstring cfg`landingdir)," into ",(asstring cfg`dbdir),"/",asstring cfg`tablename];
  dir:hsym assym cfg`landingdir;
  csvs:` sv'dir,'files where (files:key dir) like "*.csv";
  / a single-char string LITERAL (e.g. ",") is auto-atomized by q at compile time
  / (type -10h), which `enlist` alone correctly restores to a proper 1-char vector -
  / that was true for the old .q settings (parsed via `value`, so the literal's
  / compile-time atomization applied). di.util.toml's runtime-built strings are never
  / atomized this way even when logically 1 character (type 10h already), so
  / blindly enlist-ing double-wraps them. Only enlist a genuine atom.
  sep:$[0>type cfg`separator;enlist cfg`separator;cfg`separator];
  / sep/types passed explicitly - a lambda written inline in a function body does
  / NOT close over that function's plain locals in q (only true globals, like cfg
  / above, are visible from anywhere); each-iterated over csvs via x.
  raw:raze {[types;sep;x] (types;sep) 0: read0 x}[cfg[`types];sep] each csvs;
  dbdir:assym cfg`dbdir;
  tname:assym cfg`tablename;
  dates:distinct `date$raw`time;
  {[dbdir;tname;alldata;d]
    set[tname;select from alldata where d=`date$time];
    .Q.dpft[dbdir;d;`sym;tname];
    }[dbdir;tname;raw] each dates;
  logdep[`info][`loader;"load complete, partitions written: ",", " sv string dates];
  notifyhdb[];
  }

/ run is the di.torq post-init one-shot hook (see di/torq/torq.q's runhook); it loads
/ then EXITS. The loader is a one-shot batch process: it has no listening port and,
/ once notifyhdb opens a di.torq.servers handle to the hdb, that persistent handle is enough
/ to keep q alive with nothing to do (early portless/handleless versions exited on their
/ own simply because nothing was left to poll - that is not a contract to rely on). An
/ explicit exit makes "load then terminate" deterministic regardless of open handles.
/ The exit lives HERE, not in loadall, so loadall keeps its descriptive name and stays
/ re-triggerable by hand in a console (`.loader.loadall[]`) without killing the session.
run:{[] loadall[]; exit 0};

/ tell the hdb to reload, if one is configured in `connections. Uses di.torq.servers for
/ connection management (process.csv-driven) rather than a raw hopen.
notifyhdb:{[]
  if[0=count cfg`connections;
    logdep[`info][`loader;"no connections configured, skipping hdb notification"];
    :()];
  / injected di.torq.servers (di.torq ran its init; a custom process receives it in deps just like
  / a built-in module) - we only start it with our own connections, then look up the hdb handle.
  svcmod:alldeps`servers;
  (svcmod`startup)[cfg];
  wh:(svcmod`gethandlebytype)[`hdb;`any];
  if[null wh;
    logdep[`warn][`loader;"could not obtain a handle to hdb - skipping reload notification"];
    :()];
  logdep[`info][`loader;"notifying hdb to reload"];
  wh ".hdb.reload[]";
  logdep[`info][`loader;"hdb reload triggered"];
  }

\d .
