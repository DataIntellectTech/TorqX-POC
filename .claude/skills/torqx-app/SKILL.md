---
name: torqx-app
description: >
  Building and running a TorqX application: an app (like TorqX-POC) that
  composes di.torq and di.* modules from kdbx-modules. Covers setenv.sh and
  TORQX* env vars, process.csv, torqx.sh (start/stop/status/attach/devstart/
  export-systemd), the settings cascade and TOML config, custom process
  types in code/processes with .<proctype>.init[config;deps], per-proctype
  app code, deps.toml/depcheck, log rolling, discovery, chained TP and
  start order. Use when working in a TorqX app repo or debugging a TorqX
  process.
---

# TorqX Applications

A TorqX app is config plus a little custom code. The framework (`di.torq`, `di.torq.proc.*` and the library modules) lives in a separate **kdbx-modules** checkout that `$TORQXHOME` points at. Never copy framework code into the app.

**Trust the code over the docs.** Some README/torq.md statements are stale (see the end). When behaviour matters, read `$TORQXHOME/di/torq/torq.q`, `config/config.q` and the relevant `proc/<type>/` module. For module internals, use the `kdbx-modules` and `torq-module-extraction` skills in kdbx-modules.

## Layout

```
<app>/
  setenv.sh                 env vars; the only install edit is TORQXHOME
  deps.toml                 minimum versions of the di.* modules the app uses
  database.q                tickerplant schema (unkeyed tables, time,sym first)
  appconfig/process.csv     host,port,proctype,procname
  appconfig/settings/       default / <proctype> / <procname> as .toml (or .q)
  appconfig/housekeeping.csv
  code/processes/<proctype>.q   custom process types
  code/common/ code/<proctype>/ code/<procname>/   extra app code (see below)
  hdb/ tplog/ wdb/ logs/    runtime data (gitignored)
```

## Environment (`setenv.sh`)

| Var | Meaning |
|---|---|
| `TORQXHOME` | kdbx-modules checkout (default `$dirpath/../kdbx-modules`) |
| `TORQXAPPHOME` | app root (code and config) |
| `TORQXAPPCONFIG` | `$TORQXAPPHOME/appconfig` |
| `TORQXDATAHOME` | runtime data root (falls back to `TORQXAPPHOME`) |
| `TORQXSTACKID` | unique per user per host, e.g. `torqx-poc-$USER`; part of every process's identity |
| `TORQXLOGDIR` | optional; launcher logs (default `/tmp`) |
| `QPATH` | `$TORQXHOME:$HOME/.kx/mod` |

`di.torq` fails at startup if `TORQXHOME`, `TORQXAPPCONFIG` or `TORQXAPPHOME` is unset. `setenv.sh` also puts `$TORQXHOME/di/torq/bin` on `PATH`.

## `process.csv` and `torqx.sh`

Header `host,port,proctype,procname`. Keep that column order: both `torqx.sh` and `di.torq` read it by position. Port `0` means no listening port (e.g. a one-shot loader). Ports are absolute.

Run from the app directory (it sources `./setenv.sh`, or `$SETENV`):

| Command | Does |
|---|---|
| `torqx.sh start [procname]` | start one process, or all; `--tmux`/`-t` for a tmux pane; extra args pass through |
| `torqx.sh stop [procname]` | kill it and remove its tmux session (refused if a systemd unit exists) |
| `torqx.sh restart [procname]` | stop, then start |
| `torqx.sh status` | up/down + pid, `(tmux)` tags |
| `torqx.sh attach [procname]` | attach to its tmux session; no argument lists sessions |
| `torqx.sh devstart` / `devstop` / `devattach` | tmux dev-mode aliases |
| `torqx.sh export-systemd [procname]` | write `systemd/torqx-<stackid>-<procname>.service` |

- Each process runs as `QINIT=$TORQXHOME/di/torq/bin/torqx_init.q q -torqxstackid ID -proctype T -procname N [-p PORT] ...`. Its launcher log is `$TORQXLOGDIR/torqx_<stackid>_<procname>.log`.
- **`status` only checks the pid**, so a process whose `init` aborted can still show as up. To confirm a process really started, query it: `result` is defined only once `di.torq.init` has finished.
- Start order: discovery → tickerplant → chainedtp → the rest → gateway last. A backend that starts after the gateway needs ``h(`.gw.reload;`reloadend)`` on the gateway.

## Startup (`torqx_init.q` → `di.torq.init[proctype;procname;overrides]`)

1. App `deps.toml` version check
2. Resolve identity from process.csv
3. Per-process version graph
4. Build the `log` dep
5. Settings cascade, then command-line overrides
6. Build `timer`, `handlers`, `servers`; start logroll
7. Start the process:
   - built-in: `di.torq.proc.<type>` `init[config;deps]`
   - custom: load `code/processes/<proctype>.q`, then call `.<proctype>.init[config;deps]`
8. Load app code
9. `.servers.startup` / pubsub if enabled; client tracking; query log; zpsignore
10. Post-load audit
11. `.<proctype>.run[]` if defined, unless `-norun`

`overrides` may replace any of `log`, `timer`, `handlers` and `servers`.

## Configuration

**Cascade:** name-major, with each name across both roots. `builtin/default` → `app/default` → `builtin/<proctype>` → `app/<proctype>` → `builtin/<procname>` → `app/<procname>`. The builtin root is `$TORQXHOME/di/torq/settings`; the app root is `$TORQXAPPCONFIG/settings`. Within each tier, `.toml` beats `.q`. The command line comes last and wins.
- **Command line:** `-key value` must name an **existing** key; the value is parsed to that key's type. Unknown or unparsable values are logged and skipped. Reserved flags: `proctype`, `procname`, `torqxstackid`, `p`, `norun`.
- **The `config` dict** a process gets is one flat dict (plus `proctype`, `procname`, `processcsv`). A TOML `[section]` becomes a nested dict. An app section **replaces** the whole builtin section rather than merging into it, so repeat every key you need.
- **Reading a key:** always use a presence check: ``$[`k in key config;config`k;default]``.
- **`.q` settings files** are flat `name:value` lines (each value run through `value`). They are not namespaced.

**TOML limits (`di.util.toml`):** strings, longs, floats, bools, flat arrays and one level of `[section]`. Unsupported input is rejected, not mis-parsed:
- **No symbols:** they arrive as strings. Normalise at the point of use: `assym:{[x] $[11h=abs type x;x;`$x]}`, and `asstring` likewise. Don't `enlist` a string separator.
- **No timespans/datetimes:** write `"0D00:00:10"` as a string, or seconds, and convert in code.
- **No inline tables, dotted keys or `[[arrays]]`.**
- **`rolltimeoffset`:** a timespan TOML can't express. Use a `.q` settings file.

## Custom process types (`code/processes/<proctype>.q`)

Use one for app-specific processes (feeds, loaders) that aren't reusable `di.*` modules. The framework needs `.<proctype>.init[config;deps]` to exist after loading the file, and calls `.<proctype>.run[]` if that exists.

A custom process is a plain file loaded with `\l`, **not** a `use`-loaded module, so it can't drop its namespace. Wrap the file in `\d .<proctype>` … `\d .`, as `feed.q` and `loader.q` do:

```q
/ <proctype>: <purpose>

\d .myfeed

init:{[config;deps]
  / store deps and config; connect; schedule
  logdep::deps`log;
  period::$[`period in key config;config`period;1];
  svc::deps`servers;
  (svc`startup)[config];
  if[not (svc`waitfortype)[`tickerplant;30000;500];
    '"myfeed: no tickerplant after 30s"];
  h::(svc`gethandlebytype)[`tickerplant;`any];
  (deps[`timer]`addjob)[`myfeedpub;`.myfeed.publish;();period;1h;()!()];
  logdep[`info][`myfeed;"initialised"];
  };

publish:{[]
  / publish one batch; the tickerplant stamps time
  h(".u.upd";`trade;batch[]);
  };

\d .
```

- **Assigning a global** inside these functions needs `::` (`h::…` sets `.myfeed.h`). A single `:` makes a local.
- **Root tables:** bare names inside the block resolve in `.myfeed` only, with no fallback to root. Read a root table with `` get`..trade ``.
- **Names passed as symbols** (timer jobs, API symbols, anything run from outside the block) use the full name: `` `.myfeed.publish ``.
- **Reserved words** such as `log` can't be used as variable names, so the example uses `logdep`.

**Dependency contracts:**
- `log`: `` `info`warn`error ``, each `{[ctx;msg]}`.
- `timer` (di.timer): `addjob[id;func;params;period;mode;opts]`, `deletejobs`, `enablejobs`, `disablejobs`, `getactivejobs`.
  - **Period is whole seconds**, so the TorQ-style 200ms cadence isn't possible.
  - Modes: 1h = after the scheduled start, 2h = after the actual start, 3h = after the end.
- `handlers`: `register[event;phase;nm;pri;func]`, `remove[event;phase;nm]`, `list[event]`. Never assign `.z.*` directly.
- `servers`:
  - `startup[config]`
  - `getservers[pt]`
  - `gethandlebytype[pt;sel]`: `sel` is `` `any`roundrobin`last ``; returns `0Ni` if none are connected, so check it
  - `waitfortype[pt;timeoutms;pollms]`: returns a bool

A custom proctype can declare module minimums in `code/processes/<proctype>.deps.toml`.

## App code (`code/common`, `code/<proctype>`, `code/<procname>`)

These files are loaded at root with plain `\l` after the process starts, `order.txt` first and then the rest alphabetically. Settings flags control which load: `loadcommoncode` (default true), `loadprocesscode` (true), `loadnamecode` (false). Use them for query functions on the RDB/HDB, like `code/rdb/examplequeries.q`.

## Versioning (`deps.toml`)

```toml
[dependencies]
"di.torq" = "0.5.0"
"di.torq.proc.rdb" = "0.3.0"
```

These are minimum `X.Y.Z` versions, checked against each module's `VERSION` file. The check follows each module's own `deps.toml` transitively, reading from disk. All failures are reported together as `DEPENDENCY CHECK FAILED ...: X requires minimum version A, found B` (or `not found on QPATH`), and the process exits before anything else loads. A missing manifest is a no-op. When you upgrade a module in kdbx-modules, bump the pin here if the app needs the new behaviour.

## Logs

- **Default:** launcher output goes to `$TORQXLOGDIR/torqx_<stackid>_<procname>.log`.
- **Log rolling** (opt-in `[logroll]`: `enabled=true`, `dir="logs"` relative to `TORQXAPPHOME` or absolute, `suppressalias`, `forceredirect`):
  - Files are `out_<procname>_<ts>.log` / `err_<procname>_<ts>.log`, plus `out_<procname>.log` / `err_<procname>.log` symlinks.
  - Rolls daily at UTC midnight (`.logroll.rollnow[]` forces a roll).
  - Interactive and tmux sessions aren't redirected unless `forceredirect=true`.
  - Under systemd, the journal goes quiet once the redirect starts.
- **Query log:** a `[querylog]` section (`enabled`, `logtomemory`, `logtodisk`, `level`, `dir`, `flushtime`, `flushinterval`, `ignorelist`).

## Topology features

- **Discovery:** add a `discovery` row and start it first. Set `discoveryregister = true` and `connectionsfromdiscovery = true` in the app `default.toml`.
- **Chained TP:** set `tickerplanttypes = "chainedtp"` in the subscriber's settings; the chainedtp settings take `pubinterval` (whole seconds), `createlogfile` and `logdir`. A chained TP exits if it loses its upstream TP.
- **Client tracking:** always on (`.clients.clients`, `[clients]` section). `[zpsignore]` defaults to ignoring `upd` / `.u.upd`.

## Gotchas

- **Root writes from modules:** writes inside a `use`'d module land in its private namespace. Root tables and root IPC names (`upd`, `.u.upd`, `.hdb.reload`) must be written with `@[`.;…]` / `set`. This is a module-author concern, but it explains "rows vanished" bugs.
- **Tickerplant schema:** only unkeyed tables starting `time,sym` are published, and malformed ones are skipped silently. Check `database.q` when a table never appears.
- **Reserved names** (`log`, `sv`, `ss`, `string`, `cut`, `tables`) as locals can break at load time; pick distinct names.
- **Unused settings files:** a settings file whose name matches no proctype/procname in `process.csv` is ignored (e.g. `hdb1.toml` when the procname is `hdb`).
- **Heredocs:** when feeding q commands to a process via a heredoc, a line containing only `\\` must be on its own line.

## Known doc drift (code is right)

- The README gives the cascade as root-major; the code is name-major (above).
- The README lists the `deps` keys as log/timer/handlers; the code also injects `servers`.
- The README's `deps.toml` example pins `di.torq` 0.4.0; the app requires 0.5.0.
- `di/torq/torq.md` says the builtin registry holds only `hdb` and there's no depcheck, and its env table leaves out `TORQXDATAHOME`.
