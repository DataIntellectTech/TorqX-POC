# Data capture example

A TorqX capture stack built from `di.*` modules: segmented tickerplant, RDB, WDB, IDB and HDB, with a simulated feed.

```
feed1 -> stp1 -+-> rdb1 (trade, quote in memory)
               |
               +-> lvc1 (last price, bid and ask per sym, from trade and quote)
               |
               +-> wdb1 (all four tables) -> wdb/<date>/ <- idb1 (orders, depth)
                         |
                         +-> end of day -> hdb/<date>/, hdb/ohlc/ <- hdb1
```

| Process | Port |
|---|---|
| stp1 | 5401 |
| hdb1 | 5402 |
| rdb1 | 5403 |
| wdb1 | 5404 |
| idb1 | 5405 |
| feed1 | 5406 |
| lvc1 | 5407 |

## Tables

Defined in [database.q](database.q). Each row also has `time`, stamped by the tickerplant, and `sym`.

| Table | Other columns | Intraday | End of day |
|---|---|---|---|
| `trade` | `price size side` | RDB | HDB partition |
| `quote` | `bid ask bsize asize` | RDB | HDB partition |
| `orders` | `orderid side price size status` | IDB | HDB partition |
| `depth` | `level bid ask bsize asize` | IDB | HDB partition |
| `ohlc` | `date high low open close` | - | HDB top-level splayed table |

`trade` and `quote` also exist in the IDB, with no rows, because the WDB fills in every table's schema so the partition can be mounted.

## Last value cache

`lvc1` ([lvc.q](code/processes/lvc.q)) subscribes to `trade` and `quote` and keeps one row per sym in `.lvc.cache`: `lastprice`, `bid` and `ask`. A sym seen on only one table has nulls for the other's columns.

On startup it replays the tickerplant's logs for `trade` and `quote` only, oldest first, then takes live updates. The tickerplant chooses the logs and the message counts in the same call that subscribes `lvc1`, so nothing is missed or applied twice.

- **It replays all of today's logs for those tables, not just the latest hour's.** A sym that hasn't ticked this hour has its last value in an older file, so replaying only the newest file would lose it. A synthetic day of `trade` log at the feed's rate, 864,000 messages, replayed in 3.5 seconds.
- **The cache is cleared at end of day.** Yesterday's values aren't in today's logs, so they couldn't be restored after a restart.
- **A torn log is still used.** If the tickerplant dies mid-write, the replay applies every whole message in that file, logs `badtail` as an error in `lvc1`'s log, and carries on with the next file.

## Where each requirement is set

| Requirement | Setting |
|---|---|
| Log files per hour and per table | `stplgmultilog`, `stplgmultilogperiod` in [stp1.q](appconfig/settings/stp1.q) |
| Memory batch mode | `stplgbatchmode` in [stp1.q](appconfig/settings/stp1.q) |
| Publish every 50ms | `QCMD` in [setenv.sh](setenv.sh) |
| `trade` and `quote` in the RDB only | `subscribeto` in [rdb1.q](appconfig/settings/rdb1.q), `numtab` in [wdb1.q](appconfig/settings/wdb1.q) |
| `orders` and `depth` in the IDB within 5 seconds | `settimer`, `numtab` in [wdb1.q](appconfig/settings/wdb1.q) |
| All tables saved at end of day | `reloadenabled` in [rdb1.q](appconfig/settings/rdb1.q); the WDB is the only HDB writer |
| `ohlc` updated at end of day | `postreplay` in [wdb1.q](appconfig/settings/wdb1.q), [ohlc.q](code/wdb/ohlc.q) |

The day rolls at midnight UTC, the di.eodtime default. To change it, add an `eodtime` section to `stp1.q`.

## Run

`setenv.sh` expects a checkout of kdbx-modules `main`, at or after `2647306`, at `../../kdbx-main`. Edit `TORQXHOME` if yours is elsewhere.

```bash
source ./setenv.sh
torqx.sh start
torqx.sh status
```

Process logs are in `/tmp/torqx_datacapture-$USER_<procname>.log` (in bash, write `${USER}_`).

## Check it

The outputs below are from a real run. Row counts will differ.

Tickerplant logs, one per table plus an error log:

```bash
ls tplog/stp1_*/
```
```
stp1_depth20261106053538
stp1_orders20261106053538
stp1_quote20261106053538
stp1_segmentederrorlogfile20261106053538
stp1_trade20261106053538
stpmeta
```

Tickerplant settings:

```bash
q -q <<<'h:hopen`::5401; show h"`batchmode`multilog`period`timerms!(.stplg.batchmode;.stplg.multilog;.stplg.multilogperiod;system\"t\")"; exit 0'
```
```
batchmode| `memorybatch
multilog | `tabperiod
period   | 0D01:00:00.000000000
timerms  | 50i
```

The RDB has `trade` and `quote`, and neither `orders` nor `depth`:

```bash
q -q <<<'h:hopen`::5403; show h"count each `trade`quote!(trade;quote)"; show h"`orders`depth in tables`."; exit 0'
```
```
trade| 623
quote| 611
00b
```

The IDB has rows only for `orders` and `depth`:

```bash
q -q <<<'h:hopen`::5405; show h"{x!{count select from x where date=max date} each x}`trade`quote`orders`depth"; exit 0'
```
```
trade | 0
quote | 0
orders| 590
depth | 635
```

Publish a row and time how long it takes to reach the IDB:

```bash
q -q <<<'h:hopen`::5401; i:hopen`::5405; t:.z.p; neg[h](`.u.upd;`orders;(enlist`PROBE;enlist 999999999;enlist`buy;enlist 1f;enlist 1;enlist`new)); neg[h][]; while[0=i"count select from orders where date=max date,orderid=999999999";system"sleep 0.02"]; -1 "visible in idb after ",string .z.p-t; exit 0'
```
```
visible in idb after 0D00:00:01.107185467
```

The last value cache:

```bash
q -q <<<'h:hopen`::5407; show h".lvc.cache"; exit 0'
```
```
sym | lastprice bid    ask
----| -----------------------
AMZN| 180.82    180.6  180.96
GOOG| 169.26    169.14 169.48
MSFT| 399.83    399.43 400.23
IBM | 139.89    139.75 140.03
AAPL| 149.31    149.2  149.5
```

The logs it replays on a restart, which are `trade` and `quote` only:

```bash
q -q <<<'h:hopen`::5401; -1 each last each "/" vs/: string h[".stplg.replaylog`trade`quote"][;1]; exit 0'
```
```
stp1_quote20261106054824
stp1_trade20261106054824
```

Restart it, stop the feed so the values hold still, and compare the rebuilt cache with the RDB. Restart the feed afterwards with `torqx.sh start feed1`:

```bash
torqx.sh restart lvc1
torqx.sh stop feed1
q -q <<<'r:hopen`::5403; l:hopen`::5407; w:(select lastprice:last price by sym from r"trade") uj select last bid,last ask by sym from r"quote"; -1 "cache equals rdb: ",-3!(`sym xasc w)~`sym xasc l".lvc.cache"; exit 0'
```
```
cache equals rdb: 1b
```

Force an end of day in 2 seconds. This moves the tickerplant's date forward a day, so clean up afterwards:

```bash
q -q <<<'h:hopen`::5401; h"(.m.di.0eodtime.setnextroll) .z.p+0D00:00:02; .stplg.getnextendUTC[]"; exit 0'
```

Then, about 10 seconds later, check the HDB:

```bash
q -q <<<'h:hopen`::5402; show h"date"; show h"{x!{count select from x where date=max date} each x}`trade`quote`orders`depth"; show h"select from ohlc"; exit 0'
```
```
,2026.11.06
trade | 4664
quote | 4613
orders| 4606
depth | 4707
date       sym  high   low    open   close
-------------------------------------------
2026.11.06 AAPL 150.25 147.47 150.07 147.76
2026.11.06 AMZN 182.09 179.77 179.99 181.4
2026.11.06 GOOG 171.71 169.03 169.98 171.48
2026.11.06 IBM  140.59 139.31 139.95 140.49
2026.11.06 MSFT 406.53 399.63 399.92 403.61
```

Self-checks for the `ohlc` and cache logic, which need no running stack:

```bash
q test/ohlc.q -q </dev/null
q test/lvc.q -q </dev/null
```
```
ok
ok
```

## Stop and clean up

```bash
torqx.sh stop
rm -rf hdb wdb tplog
```
