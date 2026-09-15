# TorqX-POC — Demo Runbook

A practical walkthrough of the TorqX proof-of-concept: the Finance Starter Pack (FSP) real-time
capture + query stack, rebuilt from standalone `di.*` modules via dependency injection, per the
**TorQ Modularisation Plan**. Audience is assumed familiar with TorQ and the plan document.

> **Presenter note.** Commands assume you are in the `TorqX-POC` project directory. After the
> one-time `source ./setenv.sh` in §1, `torqx.sh` is on `$PATH`. Lines prefixed `#>` are the
> expected output to point at.

**Contents**
1. Cold-start install & run
2. Directory structure — how it mirrors the FSP
3. Logs & the log-rolling feature
4. The `QINIT` entry point (`torqx_init.q`)
5. tmux dev mode (`torqx.sh` attach)
6. A custom process: `feed.q`
7. Config: TOML support (a new innovation)
8. Versioning & dependency checks

---

## 0. Prerequisites & layout

TorqX ships as **two** repos. For the demo, kdbx-modules (the framework and every module it uses,
branch `feature-torqx`) is already installed on the machine; we clone only the app.

```
<parent>/
├── kdbx-modules/   # the framework + modules: di/torq/bin/torqx.sh, di/torq/bin/torqx_init.q, di/<module>/...   (installed)
└── TorqX-POC/      # THE APP we are demoing                                                          (we clone this)
```

The framework checkout is **never copied into the project** — the app is just config + a little
custom code, and points at the installed framework via one env var (§1).

---

## 1. Cold-start install & run

**Clone the app:**

```bash
cd <parent>                       # the dir containing kdbx-modules/
git clone <url>/TorqX-POC.git
cd TorqX-POC
```

**The single install edit — `setenv.sh`.** Everything about *this* deployment is derived from the
clone location automatically (`TORQXAPPHOME`, `TORQXAPPCONFIG`, `TORQXDATAHOME`, `TORQXSTACKID`).
The only thing setenv.sh can't infer is **where the framework is installed**:

```bash
# setenv.sh — the one line an installer sets:
export TORQXHOME="$dirpath/../kdbx-modules"   # sibling layout (default). If kdbx-modules is
                                              # installed elsewhere, use its absolute path.
# QPATH then resolves every di.* module from there (plus the KX-shipped modules):
export QPATH="$TORQXHOME:$HOME/.kx/mod"
```

Everything else in `setenv.sh` is generic (no user/host paths). `TORQXDATAHOME` is split out from
`TORQXAPPHOME` (mirroring TorQ's `TORQAPPHOME`/`TORQDATAHOME`) so runtime data (hdb, tp-log, wdb
working dir) can live on a separate volume in a real deployment; here they coincide.

**Source it (once, for interactive use) and start the stack:**

```bash
source ./setenv.sh
torqx.sh start          # start every row in appconfig/process.csv
torqx.sh status
#> tickerplant1    tickerplant up    pid=...
#> hdb             hdb        up    pid=...
#> feed1           feed       up    pid=...
#> rdb1            rdb        up    pid=...
#> wdb1            wdb        up    pid=...
#> gateway1        gateway    up    pid=...
#> loader1         loader     down            # one-shot loader; exits after its run hook
```

`torqx.sh` is deliberately thin: it reads `process.csv` only to enumerate rows and look up a
port; it never resolves *identity* (that's di.torq's job — §4). Start/stop one or all:

```bash
torqx.sh start rdb1     # one process
torqx.sh stop           # stop all
torqx.sh restart gateway1
```

Prove the stack is live end to end — query the gateway, which scatters across rdb (today,
in-memory) + hdb (history, on-disk) and joins:

```bash
q -q <<'EOF'
h:hopen`::5050;
neg[h](`.gw.asyncexec;"select cnt:count i by sym from trade";`rdb`hdb);
show h[];
\\
EOF
```

> The deferred-sync idiom is `neg[h](`.gw.asyncexec;query;servertypes); h[]` — send async, then `h[]`
> blocks for the joined reply. In a non-interactive heredoc, keep `\\` as the **first token on its
> own line** (a trailing `; \\` on a code line is inert and the session will hang).

---

## 2. Directory structure — how it mirrors the FSP

```
TorqX-POC/
├── setenv.sh                     # env (FSP: setenv.sh)
├── deps.toml                     # declared module versions            ← NEW vs FSP (§8)
├── database.q                    # tickerplant schema (FSP: database.q — same trade/quote schema)
├── appconfig/
│   ├── process.csv               # process registry (FSP: appconfig/process.csv)
│   └── settings/                 # per-process config  (FSP: appconfig/settings/)
│       ├── default.toml          #   app-wide defaults      (FSP: default.q)
│       ├── tickerplant1.toml     #   per-process settings   (FSP: tickerplant.q, rdb.q, ...)
│       ├── rdb1.toml  wdb1.toml  gateway1.toml  feed1.toml  hdb.toml  ...
└── code/
    └── processes/
        ├── feed.q                # custom process  (FSP: code/tick/feed.q)
        └── loader.q              # custom process  (FSP: code/processes/*)
    └── rdb/examplequeries.q      # app query code loaded into the rdb (FSP: code/rdb/)
```

**The mapping to the FSP is 1:1 in shape:** `process.csv` + `appconfig/settings/<proc>` +
`code/processes/<custom>.q` + `code/<proctype>/*.q` + `database.q` + `setenv.sh`. A TorQ engineer
finds everything where they expect it.

**What's deliberately different:**

| Aspect | FSP | TorqX-POC |
|---|---|---|
| Framework code | copied into the project (`code/`) | **zero-copy** — points at installed `kdbx-modules/` via `TORQXHOME` |
| Settings format | `.q` (executable) | **`.toml`** (inert data) — `.q` still supported (§7) |
| Process behaviour | `code/processes/<proctype>.q` | built-ins are `di.*` **modules**; only app-specific procs are files |
| Dependencies | implicit | explicit **`deps.toml`**, version-checked at startup (§8) |
| Tickerplant | segmented (STP) | classic TP (segmented is a later sprint) |
| Not yet built | discovery, monitor, DQC/DQE, sort-worker, kill, tickerlogreplay | — (deferred per plan) |

The `code/<proctype>/*.q` convention is preserved: `code/rdb/examplequeries.q` (the FSP's example
`countbysym`/`hloc`) is auto-loaded into the rdb at startup, at root, exactly as TorQ's
`.proc.loadprocesscode` does.

---

## 3. Logs & the log-rolling feature

**Default location.** `torqx.sh` launches each process detached (nohup) with stdout/stderr
redirected to `$TORQXLOGDIR` (default `/tmp`):

```bash
ls /tmp/torqx_torqx-poc_*.log
#> /tmp/torqx_torqx-poc_tickerplant1.log  ...  _rdb1.log  _gateway1.log
tail -5 /tmp/torqx_torqx-poc_gateway1.log
```

**Log rolling (`di.torq.logroll`).** An opt-in module (a design delta from the plan, which folded
rolling into eodtime — see the POC status page). A process turns it on with a `[logroll]` section;
absent/disabled is a silent no-op. Here the **hdb** opts in:

```bash
cat appconfig/settings/hdb.toml
#> [logroll]
#> enabled = true
#> dir = "logs"
```

Once enabled, the process takes over its own fd 1/2 and writes timestamped, daily-rolled files
under `TORQXAPPHOME/logs/`, with stable `out_<proc>.log` / `err_<proc>.log` symlinks pointing at
the current file (a direct port of TorQ's `fileredirect`/`rolllogauto`):

```bash
ls -1 logs/
#> out_hdb.log                                    # <- stable symlink to current
#> out_hdb_2026_07_21D00_00_00_025975000.log      # <- rolled at midnight
#> out_hdb_2026_07_20D00_00_00_001379000.log
#> err_hdb.log  err_hdb_2026_07_21D...log  ...
tail -5 logs/out_hdb.log
```

The redirect takes over from whichever supervisor (bash nohup here, systemd's journal in
production) initially owned fd 1/2 — so it works the same in both launch modes.

---

## 4. The `QINIT` entry point (`torqx_init.q`)

TorqX has **no per-process launcher files** (`start_<name>.q`). One generic entry point,
`kdbx-modules/di/torq/bin/torqx_init.q`, is loaded on demand via kdb's `QINIT` and turns a plain q session into a
TorqX process. Show that the TorqX command-line params mean nothing to q on their own:

```bash
# WITHOUT QINIT — q ignores -proctype/-procname; it's just a plain q session:
q -proctype hdb -procname hdb -q <<'EOF'
-1 "  .z.x            : ", .Q.s1 .z.x;
-1 "  di.torq loaded? : ", $[`torq in key `; "yes"; "no - plain q session"];
\\
EOF
#>   .z.x            : ("-proctype";"hdb";"-procname";"hdb")
#>   di.torq loaded? : no - plain q session
```

The args just sit unparsed in `.z.x`. Now set `QINIT` (the `torqx` alias in setenv.sh does exactly
this: `QINIT=$TORQXHOME/di/torq/bin/torqx_init.q $QCMD`) and the same args make the process resolve its
identity, run the config cascade, build the DI deps, and start the process module — dropping you at
a live `q)` console for that process:

```bash
torqx -proctype hdb -procname hdb -p 5599     # explicit identity, spare port (throwaway)
#> ... INFO hdb mounting hdb from ...
#> ... WARN logroll interactive session (stdin is a TTY) - NOT redirecting the console ...
#> torqx: started hdb hdb                       # <- torqx_init.q's confirmation line
#> q)                                           # <- live console prompt; try:  tables[]
# type  \\  (then Enter) to quit this throwaway instance
```

> **Note (ties to §3).** The hdb has `[logroll] enabled=true`. When **backgrounded** (`torqx.sh
> start`, §3) `di.torq.logroll` redirects the console to `logs/` — correct for a daemon. When run
> **interactively** like this, `di.torq.logroll`'s TTY guard detects the terminal and *skips* the
> redirect (the `WARN` line above), so you keep a usable console. (Any non-logroll proctype —
> gateway, rdb, tickerplant, … — has a normal console in both cases.)

Omitting `-proctype`/`-procname` **auto-detects** identity from `process.csv` by this session's
listening port — e.g. `torqx -p 5030` becomes `rdb1` (requires that port to be free, i.e. that
process not already running).

`torqx_init.q` is ~10 lines: parse `.Q.opt .z.x`, `tq:use\`di.torq`, `tq.init[proctype;procname;overrides]`.
`-proctype`/`-procname` are both-or-neither (omit both → auto-detect by listening port); `-norun`
skips the optional `.run` hook.

---

## 5. tmux dev mode (`torqx.sh` attach)

For local development, start processes as **attachable tmux sessions** (a live `q)` console per
process) instead of background+logfile. Use the `--tmux` flag or the `devstart`/`devstop`/`devattach`
aliases. One session per process, named `<stackid>-<proc>`:

```bash
torqx.sh devstart gateway1            # == torqx.sh start gateway1 --tmux
#> starting gateway1 (gateway) in tmux session 'torqx-poc-gateway1'...
#>   attach with: torqx.sh attach gateway1   (or: tmux attach -t torqx-poc-gateway1)

torqx.sh status
#> gateway1        gateway    up    pid=... (tmux)     # <- tagged only when the RUNNING pid is the tmux one

torqx.sh attach gateway1              # drops you at the live q) console
#  ... at the q) prompt, run e.g.:  select count i by sym from `.gw ... or any diagnostic
#  detach without stopping the process:  Ctrl-b then d
```

`stop`/`status` work identically for tmux- and nohup-started processes (discovery is by the
`-torqxstackid/-proctype/-procname` command-line signature, not the TTY). A crash stays visible in
the pane (`remain-on-exit`); output is still tee'd to the usual logfile; `stop`/`devstop` cleans up
the session:

```bash
torqx.sh devstop gateway1
torqx.sh start gateway1               # back to normal background mode for the rest of the demo
```

Sessions are intuitively named, so you can also bypass torqx.sh: `tmux attach -t torqx-poc-rdb1`.

---

## 6. A custom process: `feed.q`

Built-in proctypes (hdb/tickerplant/rdb/wdb/gateway) are `di.*` modules. Anything app-specific is a
plain file under `code/processes/<proctype>.q`, loaded by di.torq via the **same
`init[config;deps]` contract**. `feed.q` is a faithful port of the FSP feed (same data-generation
machinery), adapted to that contract.

```bash
sed -n '103,158p' code/processes/feed.q
```

**Requirements for a di.torq custom process** (point these out in the file):

- **Everything under `\d .<proctype>`** — here `\d .feed` (line 26). Publishing at a real root
  namespace, not a `use`-mangled one.
- **Required: `.<proctype>.init[config;deps]`** (line 109) — the entry point di.torq calls. `config`
  is the merged settings dict (from `feed1.toml`); `deps` is the DI dict (`log`/`timer`/`handlers`).
- **Optional: `.<proctype>.run[]`** — a post-init one-shot hook di.torq calls if present (skippable
  with `-norun`). `feed.q` has **no** run hook (it schedules its own timer job in `init`);
  `loader.q` *does* define one (`run:{[] loadall[]; exit 0}`), which is how the loader fires its
  one-shot load and then terminates — it has no listening port and holds an hdb handle open after
  `notifyhdb`, so without the explicit `exit` q would sit idle forever; hence it correctly reports
  `down` once complete. `loadall` itself has no exit, so it stays re-triggerable by hand in a console.

**Where it interfaces with TorqX** (the di.torq-forced divergences from the FSP original, all
commented in the file):

- **Injected log**: `logdep::deps\`log; logdep[\`info][\`feed;"..."]` (lines 110, 155) — not `.lg.o`.
- **Injected timer**: `(deps[\`timer]\`addjob)[\`feedpublish;\`.feed.feed;();period;1h;()!()]` (line
  153) — not `.timer.repeat`.
- **Connections via `di.torq.servers`** (lines 142–148): `svc:use\`di.torq.servers; (svc\`init)[config;deps];
  (svc\`startup)[config];` then **`(svc\`waitfortype)[\`tickerplant;timeout;500]`** (block until the
  TP is up — the modular equivalent of `.servers.startupdepcycles`) and
  `(svc\`gethandlebytype)[\`tickerplant;\`any]`.
- **Config-driven**: the FSP's hard-coded literals (`syms`/`prices`/`mode`/`cond`/... and
  `len`/`maxn`/`qpt`) are read from `feed1.toml` (lines 113–123), keeping the ported code generic.
- **Symbol normalisation**: `assyms:{[x] $[11h=abs type x;x;\`$x]}` (line 107) — TOML gives strings,
  `.q` settings give symbols; normalise at point of use so either format works.

---

## 7. Config: TOML support (a new innovation, not in the plan)

**Why.** The plan kept TorQ's `.q` settings files. But a `.q` settings file is **executable code** —
it can run arbitrary q at load. That's not hypothetical: in the FSP itself,
`settings/segmentedchainedtickerplant.q` has a live conditional and `settings/default.q` has a bare
`system"c ..."`. Config that can *execute* is a footgun for an ops/config boundary. TorqX adds a
**`di.util.toml`** parser and makes **TOML the documented default**: inert data, comment-friendly, maps
cleanly onto the flat/sectioned settings shape. (Chosen over YAML: no native q parser for either,
and TOML's grammar is far more tractable to hand-build correctly.) `.q` remains fully supported.

**The cascade.** `di.torq.config` merges, later tiers overriding earlier:
`builtin/default → builtin/<proctype> → app/default → app/<proctype> → app/<procname>` — and for
each tier it tries **`.q` first, then `.toml`** (so the two can coexist mid-migration; `.toml` wins
a clash).

**Live: add a setting, restart, see it take effect.** `feed1.toml` drives the feed's publish
cadence; the feed logs it at startup:

```bash
grep publishperiod appconfig/settings/feed1.toml
#> publishperiod = 1
grep "publishing every" /tmp/torqx_torqx-poc_feed1.log | tail -1
#>   ... INFO feed feed initialised (FSP port): 10 syms, maxn=15, qpt=5, publishing every 1s

# change it, restart just the feed, observe the new value flow through the cascade:
sed -i 's/publishperiod = 1/publishperiod = 2/' appconfig/settings/feed1.toml
torqx.sh restart feed1
sleep 2
grep "publishing every" /tmp/torqx_torqx-poc_feed1.log | tail -1
#>   ... INFO feed feed initialised (FSP port): ... publishing every 2s
# (revert:  sed -i 's/publishperiod = 2/publishperiod = 1/' appconfig/settings/feed1.toml)
```

**Legacy `.q` still works.** A pre-prepared `.q` equivalent of `rdb1.toml` is in
`docs/legacy-config-example.q` (with the TOML shown in a comment block). Parse both and compare:

```bash
q -q <<'EOF'
cfg:use`di.torq.config;
-1 "--- .q settings (symbols) ---"; show cfg.parsefile "docs/legacy-config-example.q";
-1 "--- .toml settings (strings) ---"; show cfg.parsefile "appconfig/settings/rdb1.toml";
\\
EOF
#> --- .q settings (symbols) ---
#> tickerplanttypes| `tickerplant      hdbdir| `hdb   replaylog| 1b   reloadenabled| 1b  ...
#> --- .toml settings (strings) ---
#> tickerplanttypes| "tickerplant"     hdbdir| "hdb"  replaylog| 1b   reloadenabled| 1b  ...
```

Same keys; the only difference is value *type* — `.q` symbols vs TOML strings (TOML has no symbol
type). Modules normalise with `` `$ `` at point of use, so the identical module code consumes either
format unchanged.

---

## 8. Versioning & dependency checks

Every module carries a plain-text `VERSION`; the app declares the **minimum** it needs in
`deps.toml`. (Both are design deltas from the plan, which proposed an eval'd `deps.q` — the point of
a pre-flight check is that it shouldn't require *loading* the module, and manifests shouldn't be
executable, same reasoning as §7.)

```bash
cat $TORQXHOME/di/torq/proc/rdb/VERSION $TORQXHOME/di/torq/proc/gateway/VERSION
#> 0.3.0
#> 0.2.0
sed -n '5,22p' deps.toml
#> [dependencies]
#> "di.torq" = "0.4.0"   "di.torq.proc.rdb" = "0.3.0"   "di.torq.proc.gateway" = "0.2.0"   ...
```

`di.torq.depcheck` runs at the very start of `di.torq.init` (before identity, config, or any module
load), resolves each declared module on `QPATH`, reads its `VERSION`, and enforces the minimum —
collecting **all** failures before reporting. Demonstrate an unsatisfiable dependency:

```bash
# bump a dep to a version that doesn't exist yet:
sed -i 's/"di.torq.proc.rdb" = "0.3.0"/"di.torq.proc.rdb" = "0.4.0"/' deps.toml
torqx.sh restart rdb1
torqx.sh status rdb1
#> rdb1            rdb        down            # <- refused to start
tail -4 /tmp/torqx_torqx-poc_rdb1.log
#> 'DEPENDENCY CHECK FAILED:
#>   di.torq.proc.rdb requires minimum version 0.4.0, found 0.3.0
#>   [1]  \l .../kdbx-modules/di/torq/bin/torqx_init.q

# revert and it starts clean again:
sed -i 's/"di.torq.proc.rdb" = "0.4.0"/"di.torq.proc.rdb" = "0.3.0"/' deps.toml
torqx.sh restart rdb1
torqx.sh status rdb1
#> rdb1            rdb        up    pid=...
```

(A missing module reports `... requires minimum version X, not found`; a missing `deps.toml`
altogether is a silent no-op — the whole feature is opt-in.)

---

## Teardown

```bash
torqx.sh stop            # stop the whole stack
torqx.sh status          # all down
```

For production, the same `process.csv` drives `torqx.sh export-systemd`, which emits one
`systemd --user` unit per process (journald logging, `Restart=on-failure`) — that's the deploy
path; tmux mode (§5) is dev-only.
