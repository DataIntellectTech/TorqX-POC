# Data-capture stack

A market-data capture stack built on TorqX and the `di.*` modules. A simulated feed sends four tables to a segmented tickerplant, which logs them per hour and per table and publishes them every 50ms.

| Process | Port | Role |
|---|---|---|
| `stp1` | 24100 | Segmented tickerplant, memory batch mode |
| `hdb1` | 24101 | Historical database, including the `ohlc` table |
| `wdb1` | 24102 | Writes all four tables to disk and saves them at end of day |
| `idb1` | 24103 | Serves `wdb1`'s intraday data |
| `rdb1` | 24104 | Holds `trade` and `quote` in memory |
| `lvc1` | 24106 | Caches last traded price, bid and ask per symbol |
| `feed1` | 24105 | Simulated feed |

| Table | Columns | During the day | At end of day |
|---|---|---|---|
| `trade` | time, sym, price, size, side, ex | `rdb1`, `lvc1` | `hdb1` |
| `quote` | time, sym, bid, ask, bsize, asize, ex | `rdb1`, `lvc1` | `hdb1` |
| `orders` | time, sym, orderid, side, price, size, status | `idb1` | `hdb1` |
| `depth` | time, sym, bidpx, bidqty, askpx, askqty | `idb1` | `hdb1` |

At end of day, `wdb1` also adds a row per date and symbol to `ohlc`, a splayed table built from `trade`.

On restart, `lvc1` rebuilds its cache by replaying today's `trade` and `quote` logs. Its cache clears at end of day.

## Prerequisites

- `q` on your `PATH`
- `kdbx-modules` checked out next to this repo, or `TORQXHOME` in `setenv.sh` changed to point at it
- The module versions in `deps.toml`, as minimums:

| Module | Version |
|---|---|
| `di.torq` | 0.6.0 |
| `di.torq.proc.segmentedtp` | 0.2.0 |
| `di.torq.proc.rdb` | 0.4.0 |
| `di.torq.proc.wdb` | 0.3.0 |
| `di.torq.proc.idb` | 0.1.0 |
| `di.torq.proc.hdb` | 0.1.0 |
| `di.subscriptions` | 0.2.0 |

`setenv.sh` sets `QCMD="q -t 50"`, which starts every process with a 50ms q timer. The tickerplant's publish interval comes from this timer.

## Start

Run everything from `datacapture/`. Check that the ports are free first:

```bash
. ./setenv.sh
ss -ltn | grep -E ':2410[0-7]\b' || echo "ports free"
```

Start the processes in `process.csv` order, then check them:

```bash
for p in stp1 hdb1 wdb1 idb1 rdb1 lvc1 feed1; do torqx.sh start $p; done
torqx.sh status
```

Every process should show `up`. Data and logs go in `data/`.

## Stop

```bash
for p in feed1 lvc1 rdb1 idb1 wdb1 hdb1 stp1; do torqx.sh stop $p; done
ss -ltn | grep -E ':2410[0-7]\b' || echo "ports free"
```

## Query

Open a q session with `q`, then connect to each process.

Real-time tables on `rdb1`:

```q
r:hopen 24104
r"select rows:count i by sym from trade"
r"select last bid,last ask by sym from quote"
```

Intraday tables on `idb1`:

```q
i:hopen 24103
i"select rows:count i by sym from orders where date=last .Q.pv"
i"select rows:count i by sym from depth where date=last .Q.pv"
```

Last values on `lvc1`:

```q
l:hopen 24106
l".lastvalue.cache"
```

Saved data on `hdb1`, which has partitions and `ohlc` rows after the first end of day:

```q
h:hopen 24101
h"select rows:count i by date from trade"
h"select from ohlc"
```

## Check

Run a check with `q verify.q <stage> -q`, with the stack up.

| Stage | What it does | A pass looks like |
|---|---|---|
| `live` | Shows TP settings, subscriptions and row counts | `orders` and `depth` are not in `rdb1`; `trade` and `quote` have no intraday rows in `idb1` |
| `batch` | Sends a row and looks for it in TP memory and the log | In memory and not in the log at first; 100ms later, out of memory and in the log |
| `latency` | Times 100 rows per table from send until visible in `idb1` | `max` under 5000 (ms) |
| `logs` | Lists today's logs and rows per log | One log per table per hour |
| `check` | Compares logs with the HDB for every date, and recalculates `ohlc` | `diff` of 0 for every table; `matches recalculation` shows `1b` |
| `eod1` | Brings end of day forward to 2 seconds away, then runs the same comparison for that date | Same as `check`, and `stp1` moves to the next date |

The cadence check needs its own form, because it runs for 10 seconds while listening for batches:

```bash
sleep 25 | q verify.q cadence -q
```

A pass shows a median gap of 50ms between batches.

### Compare the cache

`lvcompare` compares `lvc1` with `rdb1` and with a second cache, `lvc2`, on port 24107. Start `lvc2` with the stack up:

```bash
QINIT="$TORQXHOME/di/torq/bin/torqx_init.q" nohup $QCMD -torqxstackid "$TORQXSTACKID" -proctype lastvalue -procname lvc2 -p 24107 > data/logs/torqx_${TORQXSTACKID}_lvc2.log 2>&1 &
disown
```

Stop the feed so the stream is quiet, compare, then start the feed again:

```bash
torqx.sh stop feed1
q verify.q lvcompare -q
torqx.sh start feed1
```

All three comparisons should show `1b`.

To restart `lvc1` first, run `torqx.sh stop lvc1` and `torqx.sh start lvc1`. Once `lvc1` is back, `lvcompare` shows whether it recovered.

`q verify.q burst <seconds> <prefix> -q` sends a trade and a quote for a new symbol each time, then prints how many it sent. Use it before `lvcompare` to test with symbols that aren't overwritten by later ticks.

`lvc2` isn't in `process.csv`, so stop it by the pid on its port:

```bash
P=$(ss -ltnp | grep ':24107\b' | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2)
ps -o args= -p $P
kill $P
```

Check that the printed command line shows `-procname lvc2` and your stack id before running `kill`.

## Restart on the same day

Set `data/` aside before starting again on the same day. It holds today's HDB partition, TP logs and any test rows, and a new run would replay those logs and clash with that partition at end of day.

With the stack stopped:

```bash
mv data "data.$(date +%Y%m%d%H%M%S)"
. ./setenv.sh
```

Then start the stack as normal. `setenv.sh` creates a new `data/hdb`.

## Test results

`../REQUIREMENTS_CHECK.md` records the requirements and test results for this stack.
