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
9. A chained tickerplant (`chainedtp1`)
10. Service discovery (`discovery1`)
11. Client session tracking (`gateway1`) — ⚠️ needs di.torq 0.7.0, not yet on main

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

> **⚠️ For a demo or rehearsal, pin `TORQXHOME` to its own clone.** The sibling `kdbx-modules` is
> a *working* checkout — whoever owns it switches branches and commits in it during normal
> development, and each switch silently changes which module versions this app resolves. When the
> resolved versions stop satisfying `deps.toml`, `di.torq.depcheck` fails and **every process falls
> through to a bare q session**: no tables, no `[ERROR]` in the log (the failure is buffered and
> never flushed while the process lives), and gateway queries that *hang* rather than fail. This
> happened mid-session while preparing this runbook — the checkout moved to a branch without
> `di.torq.proc.discovery` and the whole stack quietly stopped working. Everything this app needs
> is on `main` as of `1309e9e`, so pin to `main` unless you are testing an unmerged branch.
>
> `setenv.sh` honours a pre-set `TORQXHOME`, so pin it:
>
> ```bash
> git clone --branch main --single-branch \
>   ~/bin/kdbx-modules ~/bin/kdbx-modules-demo
> export TORQXHOME=~/bin/kdbx-modules-demo      # before sourcing, and in any demo shell
> source ./setenv.sh
> ```
>
> Sanity-check what you actually resolved before demoing anything:
> ```bash
> cat $TORQXHOME/di/torq/VERSION $TORQXHOME/di/torq/servers/VERSION
> #> 0.6.0    <- needs >= 0.6.0 for discovery auto-subscribe (>= 0.7.0 for section 11)
> #> 0.5.0    <- needs >= 0.5.0 for addprocs/removeprocs
> ```

**Source it (once, for interactive use) and start the stack:**

```bash
source ./setenv.sh
torqx.sh start          # start every row in appconfig/process.csv
torqx.sh status
#> tickerplant1    tickerplant up    pid=...
#> chainedtp1      chainedtp  up    pid=...   # chains from tickerplant1 (§9)
#> hdb             hdb        up    pid=...
#> feed1           feed       up    pid=...
#> rdb1            rdb        up    pid=...
#> wdb1            wdb        up    pid=...
#> gateway1        gateway    up    pid=...
#> discovery1      discovery  up    pid=...   # service discovery (§10)
#> loader1         loader     down            # one-shot loader; exits after its run hook
```

> **Shared hosts: `TORQXSTACKID` must be unique per user.** `torqx.sh` keys both its liveness
> check and its log paths (`/tmp/torqx_<stackid>_<procname>.log`) on it, so two people running
> this repo under the same id see each other's processes as their own — `torqx.sh status` lists
> them, `torqx.sh stop` would kill them, and the second to start cannot write its logs. This has
> already happened on `homer`. `setenv.sh` therefore defaults to `torqx-poc-${USER}`. Ports are a
> separate matter: `process.csv` ports are absolute, so a second stack on one host needs its own
> port block too.

> **Debugging interactively? `unset QHOME` first.** A bare `q` in a shell that has the usual
> profile `QHOME` (e.g. an Insights install) runs **kdb+ 4.1, which has no `use` keyword** — the
> same binary reports `.z.K 4.1` with it set and `.z.K 5` without. Every `use\`di.*` then throws
> `'use` and it looks like the module system is broken. Processes launched by `torqx.sh` are
> unaffected (verified), so this only bites ad-hoc sessions:
>
> ```bash
> env -u QHOME q -q     # or: unset QHOME
> ```

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
h:hopen`::5306;
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
| Tickerplant | segmented (STP) | classic TP, **plus a chained TP** off it (§9). Segmented is built as `di.torq.proc.segmentedtp` but not wired here — `di.subscriptions` cannot yet replay its multi-logfile `subdetails` shape, so no current subscriber can sit behind one |
| Service discovery | discovery process | **wired** — `di.torq.proc.discovery` (§10) |
| Not yet built | monitor, DQC/DQE, sort-worker, kill, tickerlogreplay | — (deferred per plan) |

The `code/<proctype>/*.q` convention is preserved: `code/rdb/examplequeries.q` (the FSP's example
`countbysym`/`hloc`) is auto-loaded into the rdb at startup, at root, exactly as TorQ's
`.proc.loadprocesscode` does.

---

## 3. Logs & the log-rolling feature

**Default location.** `torqx.sh` launches each process detached (nohup) with stdout/stderr
redirected to `$TORQXLOGDIR` (default `/tmp`):

```bash
ls /tmp/torqx_${TORQXSTACKID}_*.log
#> /tmp/torqx_torqx-poc-alowry_tickerplant1.log  ...  _rdb1.log  _gateway1.log
tail -5 /tmp/torqx_${TORQXSTACKID}_gateway1.log
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

## 9. A chained tickerplant (`chainedtp1`)

`di.torq.proc.chainedtp` subscribes to the origin tickerplant as an ordinary subscriber and
**republishes** what it receives under the classic `.u.sub` / `.u.subdetails` surface. Because
that surface is identical to `di.torq.proc.tickerplant`'s, a downstream subscriber cannot tell
the two apart — `di.subscriptions` asks a chained TP for `.u.subdetails` exactly as it asks the
origin. Moving a subscriber onto it is a one-word config change, not a code change.

Wiring is a `process.csv` row plus `appconfig/settings/chainedtp1.toml`:

```toml
upstreamtype = "tickerplant"   # the PROCTYPE to chain from - di.torq.servers resolves by
                               # proctype only, there is no name-based option
tplogdir = "ctplog"            # the chain keeps its OWN log, separate from the origin's tplog/
```

Prove it is relaying — `rowcount` climbs, and it reports its own log file, not the origin's:

```bash
q -q <<'EOF'
upd:{[t;d] };                                  # asking for subdetails also subscribes you
h:hopen`::5301;
d:h(`.u.subdetails;`;`);
show `tables`rowcount`logfile#d;
\\
EOF
#> tables  | `packets`quote`trade
#> rowcount| 58
#> logfile | `:/.../TorqX-POC/ctplog/chainedtp1_2026.09.22
```

To put a subscriber behind it instead of the origin, point its `tickerplanttypes` at the chained
proctype — e.g. in `rdb1.toml`, `tickerplanttypes = "chainedtp"`. Nothing else changes.

---

## 10. Service discovery (`discovery1`)

`di.torq.proc.discovery` reads the phone book(s), **dials every row itself**, and **pushes** the
live rows into each subscriber's own `.torq.servers` registry. Subscribers never dial back and
never self-register — there is deliberately no `register` entry point.

**A consumer opts in with config alone.** The consumer half lives in `di.torq` (≥ 0.6.0), not in
the discovery module, so it works for every process type at once. In `rdb1.toml`:

```toml
discoverywant = "ALL"          # or e.g. "rdb hdb" to narrow
```

Use `discoverywant` rather than listing `discovery` in `connections`: a built-in process type
replaces the flat `connections` key with its own role list (the rdb's is `tickerplanttypes` +
`hdbtypes`), so a `connections` entry would never reach `di.torq.servers`.

**Two phone books.** Discovery always reads `process.csv`, and — with `tracknontorqprocess`
(default on) — also `nontorqprocess.csv` beside it, in the same `host,port,proctype,procname`
format. No consumer ever reads that second file, which is what makes it a genuine discovery
demo rather than a restatement of config. Change detection is a **content diff on every tick**
(`retryperiod`, set to 5s here) — there is no mtime or inotify watch.

**The demo.** With the stack up, start something nothing has been told about, then add it to the
second phone book:

```bash
q -p 5310 -q &                                             # a bare, non-TorqX process
echo 'localhost,5310,analytics,analytics1' >> appconfig/nontorqprocess.csv
```

Within a tick it appears in the rdb's registry — a process the rdb was never configured to know
(its config names only `tickerplant` and `hdb`):

```bash
q -q <<'EOF'
upd:{[t;d] };
h:hopen`::5304;
show h"select procname,proctype,hpup from .m.di.0torq.0servers.SERVERS";
\\
EOF
#> analytics1   analytics   :localhost:5310      <- pushed, never declared to the rdb
```

Now delete that line from `nontorqprocess.csv`, **leaving the process running**. Within a tick it
is evicted everywhere. Eviction is keyed on the phone book, not on liveness — a listed process
that is merely *down* is retained and retried, an *unlisted* process is decommissioned:

```
[servers]   removeprocs: 1 row(s) removed: analytics1/analytics@:localhost:5310
[discovery] evicted 1 row(s) no longer in any phone book: analytics1/analytics@:localhost:5310
[discovery] pushed 7 row(s) across 1 subscriber(s); 7 live service(s) known
```

> **Known limitation — the gateway does not route to a discovered backend** until its own EOD
> reload or a restart. `di.torq.proc.gateway` registers its backends into `di.serverselect` only
> in `registerbackends[]`, which runs at init and at reload-end — not on every registry change.
> So a backend that connects after gateway init (a discovered one, or just an rdb restarted
> mid-session) sits live in the gateway's registry but absent from its routing table. This
> predates discovery and is not caused by it. Force a rebuild with:
>
> ```q
> h:hopen`::5306; h(`.gw.reload;`reloadend)      / re-runs registerbackends[]; safe on a live gateway
> ```
>
> **The sharper edge, measured: restarting a backend makes the gateway HANG, not just miss it.**
> After `torqx.sh restart rdb1` the gateway's routing table still holds the dead handle, and
> `.gw.asyncexec` passes a `0Wn` timeout — so a client query against `` `rdb `` blocks
> indefinitely rather than erroring. A `.gw.reload[`reloadend]` clears it immediately. Treat
> "restart any backend → reload the gateway" as a standing rule, and be aware of it before
> restarting anything mid-demo.

### Failover onto a discovered backend

Measured, and worth knowing before demoing it: **`di.serverselect` picks one server per
proctype — it does not fan out across duplicates.** A second rdb therefore does *not* double a
`count` and does *not* add a third row to a scatter-gather result; six consecutive queries all
went to the same rdb. The payoff of a discovered second backend is **redundancy**, and the way
to show it is failover:

```bash
# 1. start an rdb that is in NO phone book and no process.csv row
env -u QHOME QINIT="$TORQXHOME/di/torq/bin/torqx_init.q" \
  q -torqxstackid "$TORQXSTACKID" -proctype rdb -procname rdb2 -p 5308 &

# 2. tell only discovery about it
echo 'localhost,5308,rdb,rdb2' >> appconfig/nontorqprocess.csv     # wait one tick (5s)

# 3. it reaches the gateway's REGISTRY but not yet its routing table
#>   registry: rdb1 connected=1, rdb2 connected=1
#>   gateway log: "registered 2 backend server(s)"

# 4. rebuild the routing table
q -q <<'EOF'
h:hopen`::5306; h(`.gw.reload;`reloadend); \\
EOF
#>   gateway log: "registered 3 backend server(s)"

# 5. kill the primary - queries keep working, answered by the discovered rdb
torqx.sh stop rdb1
q -q <<'EOF'
h:hopen`::5306;
neg[h](`.gw.asyncexec;"([]pid:enlist .z.i; n:enlist count trade)";enlist`rdb);
show h[];
\\
EOF
#> pid     n
#> ------------
#> 3798829 8503        <- rdb2's pid: a process the gateway was never configured to know
```

The gateway requires `discoverywant` in its own settings to receive the push at all (it is set in
`gateway1.toml`); opting in the rdb alone is not enough.

---

## 11. Client session tracking (`gateway1`) — ⚠️ needs di.torq 0.7.0, not yet on main

> ### ⚠️ NOT LIVE YET — needs `di.torq` 0.7.0, which is not on main
>
> The `[clienttracking]` section is already written into `gateway1.toml`, but the hook that reads
> it (`initclienttracking`) landed in **`di.torq` 0.7.0**, and `deps.toml` pins **0.6.0** — what
> is actually on main today.
>
> On 0.6.0 this section is read by nobody. No module loads, no handlers register, and **there is
> no warning**: a process that does not know a settings section exists cannot tell you it ignored
> one. Do not demo this yet, and do not spend time debugging why `getclients[]` is missing — it is
> missing because nothing wired it.
>
> **To turn it on**, in one commit: land the `initclienttracking` hook on `di.torq` (raising it to
> 0.7.0), then raise the `di.torq` pin in `deps.toml` to `"0.7.0"`. Everything below then works as
> written — it has been verified end to end against `main` + that hook.
>
> Pinning 0.7.0 *before* the hook lands is the wrong fix: depcheck runs first and fails, so every
> process in the stack falls through to a bare q session with no tables and no error in the log.

`di.clienttracking` is not a process type — it is an opt-in capability wired into an existing
process, exactly like `di.torq.logroll`. It is switched on by the presence of a
`[clienttracking]` section, and `di.torq` (>= 0.7.0) does the wiring generically; no app code.

```toml
# appconfig/settings/gateway1.toml
[clienttracking]
enabled = true
retain = "0D02:00:00"
```

The gateway is the natural host — it is the client-facing process, so these are real end-user
sessions. Every connection the README's own demo query makes shows up here:

```bash
q -q <<'EOF'
upd:{[t;d] };
h:hopen`::5306;
show h"(.m.di.0clienttracking.getclients)[]";
\
EOF
#> w  ipa       u      a          startp                          endp
#> -----------------------------------------------------------------------------------------
#> 9  127.0.0.1 alowry 2130706433 2026.09.22D21:14:25.454793396
#> 12 127.0.0.1 alowry 2130706433 2026.09.22D21:14:29.859076301   2026.09.22D21:14:33.100...
```

`w` is the handle, `ipa`/`u` the client's IP and user, and `endp` is populated once the session
closes — so the table shows live *and* recently-closed sessions (`retain` controls how long a
closed one is kept).

**The opt-in really is opt-in**, which is worth showing directly — the module is not even loaded
on a process without the section:

```bash
q -q <<'EOF'
upd:{[t;d] };
r:hopen`::5304; show r"`0clienttracking in key `.m.di"; hclose r;   / rdb1  -> 0b
g:hopen`::5306; show g"`0clienttracking in key `.m.di"; hclose g;   / gateway1 -> 1b
\
EOF
```

> **What is inert, and why.** `maxidle` and `trackusage` are accepted but do nothing on a stock
> TorqX stack: both need something to own the `exec` phase on `.z.pg`/`.z.ps`, and neither
> `di.torq.proc.gateway` nor `di.torq` claims one today. Session tracking — open/close, IP, user —
> works regardless and is what this demonstrates. That is a gap in the stack (it waits on a
> `di.permissions`-style owner), not in `di.clienttracking`.

---

## Teardown

```bash
torqx.sh stop            # stop the whole stack
torqx.sh status          # all down
```

For production, the same `process.csv` drives `torqx.sh export-systemd`, which emits one
`systemd --user` unit per process (journald logging, `Restart=on-failure`) — that's the deploy
path; tmux mode (§5) is dev-only.
