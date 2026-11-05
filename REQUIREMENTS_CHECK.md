# Data-capture stack: requirements check

The app is in `datacapture/`, on branch `data-capture-1`. All proofs are from two live runs on 2026-11-05, stack `datacapture-alowry`: the stack on ports 24100-24105 (data kept in `datacapture/data.run1/`), and a later run that added the last-value subscriber on 24106 and a control on 24107 (data in `datacapture/data/`). The stack is now stopped.

Re-run any proof from `datacapture/` with the stack up: `q verify.q <stage> -q`. The stages are `live`, `batch`, `latency`, `logs`, `check` and `lvcompare`, plus `sleep 25 | q verify.q cadence -q`. `q verify.q burst <seconds> <prefix> -q` sends unique-symbol rows. `eod1` and `eod2` roll the day.

## Summary

| # | Requirement | Result |
|---|---|---|
| 1 | Segmented TP, RDB, IDB, WDB, HDB | PASS |
| 2 | Four defined tables | PASS |
| 3 | All tables persisted to disk at end of day | PASS, with roll forced (see Limits of the proof); see finding F1 |
| 4 | Tables A and B in the RDB, everything else straight to the IDB | PASS |
| 5 | TP logs per hour and per table | PASS, real clock roll at 12:00 |
| 6 | TP in memory batch mode | PASS |
| 7 | TP publishes every 50ms | PASS, but needed a `torqx.sh` workaround (F2) |
| 8 | Data in the IDB within 5 seconds | PASS, max 3.88s; see F3 |
| 9 | Top-level splayed HLOC per date and instrument in the HDB, updated at end-of-day save | PASS, with roll forced (see Limits of the proof) |
| 10 | Real-time subscriber caching last traded price, bid and ask per symbol | PASS |
| 11 | Subscriber fully recoverable by replaying recent logs, only for the tables it needs | **FAIL** across a roll because of F1; PASS in every other restart test |

Ground rules:

| Rule | Result |
|---|---|
| Changes on `data-capture-1`, nothing pushed | PASS: committed locally at your request after each run |
| `kdbx-modules` read-only | PASS: `git status --short` shows 0 changes, HEAD still `b603445` |
| Own stack id and free ports | PASS: `ss -ltn` showed the ports free before each start and after each stop |
| No kill by name match | PASS: stopped with `torqx.sh stop`, per process. `torqx.sh` itself finds pids with `pgrep -f`, scoped to the stack id. The `lvc2` control and the `kill -9` of `lvc1` used the pid on their own port, with its command line checked first. The other stack, `torqx-poc-alowry`, still had 10 processes up afterwards |

## Framework findings

**F1. Memory batch mode can lose rows from the TP log at a roll.** This is a defect in the framework and I have not worked around it. `.stplg.endofday` and `.stplg.stpeoperiod` (`di/torq/proc/segmentedtp/stplog.q`) publish the in-memory buffer with `pubclear` without writing it to the log. If an update arrives after the roll time while earlier rows are still buffered, those rows reach subscribers and the HDB but never reach a log. A restart that replays the logs then loses them. It is confirmed at both end of day and a real hour roll. At end of day I reproduced it on purpose with `eod2`:

```
--- buffered row -4000001 in hdb partition 2026.11.06
date       sym      orderid
2026.11.06 ROLLTEST -4000001

--- buffered row in the tp logs of 2026.11.06 (count)
0

--- rows per table: tp logs vs hdb partition 2026.11.06
tbl   | logrows hdbrows diff
depth | 3095    3095    0
orders| 3095    3096    1
quote | 2995    2995    0
trade | 2995    2995    0
```

At the real 14:00 hour roll, with `verify.q burst` running across the boundary, 26 rows on 2026.11.05 reached the HDB but no log, all stamped 13:59:59.989 to .997:

```
tbl    second  | rows
depth  13:59:59| 5
orders 13:59:59| 5
quote  13:59:59| 8
trade  13:59:59| 8
```

The `trade` and `quote` rows are 3 burst symbols plus a 5-row feed batch; the `orders` and `depth` rows are the same feed batch. The window is at most one 50ms batch per roll, and it needs an update to arrive just after the roll. The burst made that far more likely: the ordinary feed alone did not trigger it at the 12:00 roll, and the timer-path end of day also lost nothing (2026.11.05 in the first run reconciled to diff 0). Anything that replays these logs is exposed; I measured the effect on the last-value subscriber (requirement 11) but did not test it on the RDB or WDB.

**F2. `torqx.sh` cannot pass `-t`.** `di/torq/bin/torqx.sh` treats `-t` as `--tmux`, so `torqx.sh start stp1 -t 50` would start a tmux session and not set the timer (read from source, not run). `torq.q` also stamps `timerms` from the command line after the settings cascade, so settings can't set it either. The workaround is `QCMD="q -t 50"` in `datacapture/setenv.sh`. It gives every process in the stack a 50ms q timer, though only the TP's batch job needs that value.

**F3. The TP or host stalled twice, cause not found.** TP-stamped times show no rows on any table for 2.87s at 12:02:29 and 1.62s at 11:39:04. My tracers and the feed are separate senders and both went quiet, so the stall is at the TP or the host, not in the IDB path. The 2.87s stall is what produced the 3.88s latency maximum. Disk on this host is 98% full and other stacks are running, but I have not shown that as the cause. A longer stall could break the 5s limit.

**F4. Smaller items.**
- An empty `heartbeat` table exists in every process, even with `heartbeatenabled = false`, because the framework's heartbeat module defines it. It shows up in `tables[]` on the RDB, IDB and HDB. The WDB doesn't persist it.
- After the first day roll, the TP opens an empty `stp1_heartbeat...` log. It doesn't do this on the first day.
- The repo-root `deps.toml` pins `di.torq` 0.7.0, but the `kdbx-modules` checkout is 0.6.0 and one commit behind origin. So `datacapture/deps.toml` pins 0.6.0. The root app's pin would fail its dependency check on a fresh start.
- The root `.gitignore` rule `wdb/` matches at any depth and would have dropped `datacapture/code/wdb/`. `datacapture/.gitignore` re-includes it.

## Proof by requirement

### 1. Processes
`torqx.sh status`, plus queries over IPC to each process:
```
stp1            segmentedtp up    pid=790902
hdb1            hdb        up    pid=790967
wdb1            wdb        up    pid=791012
idb1            idb        up    pid=791068
rdb1            rdb        up    pid=791113
feed1           feed       up    pid=791166
```
`grep -ci error` on all six process logs returned 0 at the end of the run.

### 2. Tables
Defined in `datacapture/database.q`; see Assumptions for the columns.

### 3. Persisted at end of day
`q verify.q eod1 -q`, then `q verify.q check -q`. Rows in the TP logs against rows in the HDB:
```
--- rows per table: tp logs vs hdb partition 2026.11.05
tbl   | logrows hdbrows diff
depth | 59491   59491   0
orders| 61493   61493   0
quote | 59290   59290   0
trade | 59290   59290   0
```
```
data/hdb/2026.11.05: depth orders quote trade
```
After the roll, stp1 and wdb1 were on 2026.11.06, idb1 had rolled to 2026.11.06, and rdb1 went from 59240 rows to 85, keeping only new-day rows.

### 4. Routing
`q verify.q live -q`, taken before end of day:
```
--- subscriptions held by rdb1, then wdb1
rdb1: stp1 trade, stp1 quote
wdb1: stp1 depth, stp1 orders, stp1 quote, stp1 trade

--- rdb1 tables and rows        --- idb1 tables and rows
heartbeat| 0                    depth    | 1775
quote    | 1790                 heartbeat| 0
trade    | 1790                 orders   | 3776
                                quote    | 0
                                trade    | 0
```
`orders` and `depth` are not in the RDB. `trade` and `quote` have no intraday rows in the IDB.

### 5. Hourly, per-table logs
`q verify.q logs -q` at 12:00:20, after a real clock roll with nothing forced:
```
seq logname                   start                         end                           tbls
0   stp1_depth20261105112104  2026.11.05D11:21:04.632594815 2026.11.05D12:00:00.019319675 depth
0   stp1_orders20261105112104 2026.11.05D11:21:04.632594815 2026.11.05D12:00:00.019319675 orders
0   stp1_quote20261105112104  2026.11.05D11:21:04.632594815 2026.11.05D12:00:00.019319675 quote
0   stp1_trade20261105112104  2026.11.05D11:21:04.632594815 2026.11.05D12:00:00.019319675 trade
1   stp1_depth20261105120000  2026.11.05D12:00:00.019319675                               depth
1   stp1_orders20261105120000 2026.11.05D12:00:00.019319675                               orders
1   stp1_quote20261105120000  2026.11.05D12:00:00.019319675                               quote
1   stp1_trade20261105120000  2026.11.05D12:00:00.019319675                               trade
```
```
file                      tbl    rows
stp1_depth20261105112104  depth  58566
stp1_depth20261105120000  depth  520
stp1_orders20261105112104 orders 60568
stp1_orders20261105120000 orders 520
stp1_quote20261105112104  quote  58365
stp1_quote20261105120000  quote  525
stp1_trade20261105112104  trade  58365
stp1_trade20261105120000  trade  525
```
The first file of a run is named for the start time (11:21:04) and later files for the hour. The directory also holds `stpmeta` and an error log, which was empty in this run (8-byte header).

### 6. Memory batch
`q verify.q batch -q`:
```
batchmode     | `memorybatch

--- one sync call on stp1: send a row, read memory and the log size
rowinmemory   | 1
logsizechanged| 0

--- immediately after, reading the log: row in log?
0b

--- 100ms later: row in memory on stp1? row in log?
rowinmemory| 0
rowinlog   | 1
```

### 7. Publish every 50ms
`sleep 25 | q verify.q cadence -q`, sending one row every 5ms and measuring arrivals at a subscriber:
```
timerms | 50i
stpzts  0D00:00:00.050000000 mode 1

--- gaps between orders batches at a subscriber (ms)
batches| 197
min    | 49
median | 50
p99    | 51
max    | 51
```

### 8. Within 5 seconds in the IDB
`q verify.q latency -q`. 100 tracer rows per table with the feed running, timed from send until a query on idb1 returns the row:
```
before end of day
tbl    samples min median p99  max
orders 100     148 1023   1046 1047
depth  100     148 1024   1047 1047

after the IDB rollover
tbl    samples min median p99  max
orders 100     266 1030   1042 3878
depth  100     267 1030   1042 3879
```
All times are in ms. The maximum is explained in F3.

### 9. HLOC table
`q verify.q check -q`:
```
hdb1 tables:  `depth`heartbeat`ohlc`orders`quote`trade
partitioned:  `depth`orders`quote`trade        (ohlc is not partitioned)
on disk:      data/hdb/ohlc/  .d close date high low open sym

date      | rows
2026.11.05| 5
2026.11.06| 5
2026.11.07| 5

date       sym  high   low    open   close
2026.11.05 AAPL 183.87 173.12 180.02 174.34
2026.11.05 AMD  125.45 119.9  120    123.05
2026.11.05 GOOG 141.83 136.29 139.99 137.29
2026.11.05 IBM  194.41 187.71 189.94 190.71
2026.11.05 MSFT 411.63 391.82 409.92 396.83
...
--- matches recalculation from hdb trade?
1b
```
The table gained 5 rows at each end of day. It is written by `.ohlc.save` (`datacapture/code/wdb/ohlc.q`), called from the WDB's `postreplay` hook after the partition moves into the HDB and before the HDB reloads.

### 10. Last-value subscriber
`lvc1` (`datacapture/code/processes/lastvalue.q`, port 24106) subscribes only to `trade` and `quote` and keeps `.lastvalue.cache`, with `ltp`, `bid` and `ask` per symbol. Partial updates don't overwrite each other, checked with a fresh symbol each way:
```
quote then trade   UPSERTA|      10  11   ->  UPSERTA| 10.5 10  11
trade then quote   UPSERTB| 10.5          ->  UPSERTB| 10.5 10  11
```

### 11. Recovery
`lvc1` was restarted and compared with `q verify.q lvcompare -q` against `lvc2` (same code, never restarted) and against `rdb1`'s tables, which don't share its code. The feed was stopped before each comparison so the stream was quiet. After tests 1, 2, 4 and 6, a fresh symbol confirmed `lvc1` took live updates once replay finished.

| # | Test | Result | Evidence |
|---|---|---|---|
| 1 | Clean restart, feed running | PASS | Match on all 8 symbols |
| 2 | `kill -9`, feed running | PASS | Match on all 9 symbols |
| 3 | Only needed tables | PASS | `strace`: TP logs opened were `stp1_quote20261105133139` and `stp1_trade20261105133139` only; 0 opens of `orders` or `depth` logs |
| 7 | Unique-symbol rows sent throughout 5 restarts | PASS | 7,513 symbols sent; `lvc1`, `lvc2` and `rdb1` match on all 7,522 symbols |
| 4 | Restart after the real 14:00 roll | PASS | 4 log files replayed (2 per table); `OLDHOUR`, last updated at 13:58, recovered; all non-burst symbols match |
| 5 | Burst across the 14:00 roll, then restart | **FAIL** | 3 of 745 burst symbols lost (below) |
| 6 | Forced end of day, then restart | PASS | Cache went from about 8,266 symbols to the new day's 5; only the new day's logs replayed; match on all 6 symbols |

Test 5, from `verify.q lvcompare` and a scan of the logs:
```
syms: lvc1 8266 | lvc2 8269 | rdb1 8269
rows in lvc2 not in lvc1:
H447 447 446.5 447.5
H448 448 447.5 448.5
H449 449 448.5 449.5
occurrences of those syms in the logs: 0
```
A symbol is affected only if its last update before the restart was in the final batch before a roll. The 5-row feed batch lost in the same roll did no lasting harm, because later ticks overwrote `AMD` and `GOOG`. Cause: F1.

Not tested for the subscriber:
- a natural midnight roll; test 6 was forced
- `lvc1` across a TP restart (`autoreconnect` is off)
- a restart during a roll
- sustained load; `verify.q burst` managed about 250 rows per second per table, because each sleep spawns a shell, not the 1,000 per second planned
- the cache at exactly zero at end of day; the first check came at 14:06:07, within 6 seconds of the check before the roll, and by then the feed had refilled it to 5 symbols, with the old ones gone

## Limits of the proof

- **End of day was forced.** Midnight UTC was 12 hours away, so I set the TP's `nextroll` over IPC. The framework's own roll code then ran (`checkends`, and the WDB's save, sort, move and reloads). A natural midnight roll was not observed.
- **Dates 2026.11.06 and 2026.11.07 are artefacts of forcing.** Their rows carry 2026.11.05 timestamps. All three partitions came from one clock day.
- **One extra roll was my mistake.** I piped `verify.q eod2` to `head` as a quick check, and that still fired a third end of day, for 2026.11.07. It ran the same update path and reproduced F1 again (diff 1 on `orders`).
- **Test rows are in the data.** Tracer rows and test syms (`BATCHTEST`, `CADENCE`, `TRACER`, `ROLLTEST`) are in `orders` and `depth`, so those exceed the feed's row counts. They are not in `trade`, so the HLOC figures are unaffected.
- **Not tested:** restart recovery of the RDB or WDB, and running for longer than about 45 minutes in either run.
- **Linting:** `ohlc.q` is clean under qlint. `feed.q` and `verify.q` report `UNINDENTED_CODE`, which at the checked positions in `feed.q` falls on top-level definitions at column 1, because the snippet linter reads a whole file as one expression. `verify.q` also reports `MISSING_SEMICOLON` warnings, not individually reviewed. `lastvalue.q` reports the same two kinds plus 5 `UNUSED_PARAM` and 5 `UNUSED_VAR` warnings, none individually reviewed. All three files ran as intended.

## Assumptions

1. **Table definitions** (A to D, `time` stamped by the TP):

   | | Table | Columns | Route |
   |---|---|---|---|
   | A | `trade` | time, sym, price, size, side, ex | RDB; disk at EOD |
   | B | `quote` | time, sym, bid, ask, bsize, asize, ex | RDB; disk at EOD |
   | C | `orders` | time, sym, orderid, side, price, size, status | IDB |
   | D | `depth` | time, sym, bidpx, bidqty, askpx, askqty | IDB |

2. **"Within 5 seconds in the IDB" applies to C and D.** A and B are not written intraday, so the IDB shows them with 0 rows until end of day and no row appears in both the RDB and the IDB.
3. **The WDB persists A and B too.** It subscribes to all four tables and is the only writer of `hdb/sym`, as the framework recommends. As a result it holds A and B in memory all day alongside the RDB, which uses more memory than a design where only the RDB holds them.
4. **HLOC comes from `trade.price`**, with instrument meaning `sym`. Open and close are the first and last trade by time in the sorted partition. The date is the partition date.
5. **The app lives in a new `datacapture/` directory.** The live `torqx-poc-alowry` stack uses the repo-root `appconfig/`, `hdb/`, `wdb/` and `tplog/`, so those were left untouched.
6. **Left out because the brief doesn't ask for them:** gateway, discovery, housekeeping, chained TP, and permissions. The example has no authentication, and every process is open to anyone who can reach its port.
7. **The feed is simulated:** 5 rows per table every 200ms across 5 symbols.
8. **"Most recent log files" means all of today's logs for `trade` and `quote`** (the TP's `stplgreplayperiod = day` default). Replaying only the current hour would lose any symbol that hasn't updated this hour.
9. **The last-value cache clears at end of day.** A symbol has no values until its first update of the new day. To be confirmed with Jonny.
10. **Flush settings:** `settimer = 1` second, which is what gives the roughly 1s typical IDB latency. Any flush interval under about 4s would meet the requirement in normal running.
