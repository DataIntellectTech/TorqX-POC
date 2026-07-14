/ Simulated real-time feed for the TorqX-POC. A close PORT of the Finance Starter Pack
/ feed (TorQ-Finance-Starter-Pack/code/tick/feed.q): the data-generation machinery
/ (symbol universe, price random-walk, skew weights, batch/t/q/feed) is reused verbatim
/ so downstream demos/queries that depend on relative volumes, price drift, trade/quote
/ price relationships, condition codes and srcs behave identically.
/ ---
/ Deliberately NOT a reusable di.* module - it is tied to THIS app's schema (trade/quote
/ in database.q, which is the FSP schema), so it lives as a custom process in
/ code/processes/ alongside loader.q, loaded by di.torq via .feed.init[config;deps].
/ ---
/ Divergences from the FSP original, each forced by di.torq/TorqX (not stylistic):
/   1. everything lives under \d .feed (custom-process convention), not root.
/   2. the literals of FSP lines 4-22 (syms/names/prices/mode/cond/ex/src/side) and the
/      len/maxn/qpt constants are read from feed1.toml, matching the FSP values exactly.
/   3. connection is via di.servers (init/startup/waitfortype/gethandlebytype, proctype
/      `tickerplant) instead of .servers.startupdepcycles + .servers.gethandlebytype
/      [`segmentedtickerplant;`any].
/   4. publishing is scheduled via the injected di.timer (whole-second granularity)
/      instead of .timer.repeat at 0D00:00:00.200 - so the cadence is coarser, but the
/      per-fire feed[] logic (and thus every volume/price relationship) is unchanged.
/   5. FSP's `init` (a manual historical-backfill routine) is renamed `backfill` here,
/      because di.torq requires .feed.init to be the [config;deps] process entry point.
/ The trade/quote batches carry NO time column; di.tickerplant.upd stamps time itself
/ (keeping replay idempotent), exactly matching what the FSP tickerplant does with .u.upd.

\d .feed

/ --- config-driven state (populated by init from feed1.toml; FSP lines 4-22,73,76,77) -
s:`symbol$();       / sym universe            (FSP `s`)
n:();               / security names          (FSP `n`; defined-but-unused, kept for parity)
p:`float$();        / starting prices         (FSP `p`)
m:"";               / mode chars              (FSP `m`)
c:"";               / condition chars         (FSP `c`)
e:"";               / exchange chars          (FSP `e`)
src:`symbol$();     / sources                 (FSP `src`)
side:`buy`sell;     / sides                   (FSP `side`)
len:10000;          / prices generated per batch (FSP line 73)
maxn:15;            / max trades per tick        (FSP line 76)
qpt:5;              / avg quotes per trade       (FSP line 77)

/ mutable generation state (all amended via :: inside batch, verified to target .feed.*)
cnt:0; qx:(); qb:(); qa:(); qp:(); qn:0;
weight:(); volmap:()!(); bidmap:()!(); askmap:();
weightedsyms:(); sideweight:(); sidemap:()!(); srcweight:(); srcmap:()!();
h:0Ni;              / tickerplant handle (FSP `h`)

/ --- FSP generation machinery, ported verbatim (init.q section, FSP lines 26-32) -------
pi:acos -1
gen:{exp 0.001 * normalrand x}
normalrand:{(cos 2 * pi * x ? 1f) * sqrt neg 2 * log x ? 1f}
randomize:{value "\\S ",string "i"$0.8*.z.p%1000000000}
rnd:{0.01*floor 0.5+x*100}
vol:{10+`int$x?90}

/ returns list where count of each item is given by random permutation of integer weights
/ (FSP line 46)
skewitems:{[weights;items]raze weights#'neg[count items]?items}

/ generate a batch of prices (FSP lines 60-70). qx index, qb/qa margins, qp price, qn pos
batch:{
 d:gen x;
 qx::x?weightedsyms;
 qb::rnd x?1.0;
 qa::rnd x?1.0;
 n:where each qx=/:til cnt;
 s:p*prds each d n;
 qp::x#0.0;
 (qp raze n):rnd raze s;
 p::last each s;
 qn::0}

/ trade batch of x rows (FSP lines 80-83): sym price size stop cond ex side (no time)
t:{
 if[not (qn+x)<count qx;batch len];
 i:qx n:qn+til x;qn+:x;
 (s i;qp n;`int$volmap[s i]*x?99;1=x?20;x?c;e i;raze 1?'sidemap[s i])}

/ quote batch of x rows (FSP lines 85-88): sym bid ask bsize asize mode ex src (no time)
q:{
 if[not (qn+x)<count qx;batch len];
 i:qx n:qn+til x;p:qp n;qn+:x;
 (s i;p-qb n;p+qa n;`long$bidmap[s i]*vol x;`long$askmap[s i]*vol x;x?m;e i;raze 1?'srcmap[s i])}

/ one publish tick (FSP lines 90-92): randomly a trade OR quote batch, over the handle
feed:{h$[rand 2;
 (".u.upd";`trade;t 1+rand maxn);
 (".u.upd";`quote;q 1+rand qpt*maxn)];}

/ same, but prepending an explicit timestamp column - used by backfill (FSP lines 94-96).
/ di.tickerplant.upd keeps a leading timestamp as-is, so backfilled history stays put.
feedm:{h$[rand 2;
 (".u.upd";`trade;(enlist a#x),t a:1+rand maxn);
 (".u.upd";`quote;(enlist a#x),q a:1+rand qpt*maxn)];}

/ manual historical backfill (FSP's `init`, renamed - di.torq owns .feed.init). Not
/ auto-called; invoke by hand for a demo that wants a pre-populated morning of data.
backfill:{
 o:"p"$9e5*floor (.z.P-3600000)%9e5;
 d:.z.P-o;
 len:floor d%113;
 feedm each `timestamp$o+asc len?d;}

/ --- di.torq entry point --------------------------------------------------------------

/ coerce a config list to symbols whether it came from .toml (strings) or .q (symbols):
/ `$ is not idempotent on symbols, so type-check first (same idiom as loader.q).
assyms:{[x] $[11h=abs type x;x;`$x]}

init:{[config;deps]
  logdep::deps`log;

  / load the FSP literals from config (feed1.toml), matching FSP lines 4-22,73,76,77
  s::assyms config`syms;
  n::config`names;
  p::"f"$config`prices;
  m::config`mode;
  c::config`cond;
  e::config`ex;
  src::assyms config`src;
  side::assyms config`side;
  len::"j"$config`len;
  maxn::"j"$config`maxn;
  qpt::"j"$config`qpt;

  / weight/skew setup (FSP lines 26,34,38-55) - relocated into init because it depends on
  / the config-supplied s/side/src/cnt; the code itself is the FSP code unchanged.
  cnt::count s;
  randomize[];
  weight::0.1*1+neg[cnt]?2*cnt;
  volmap::s!neg[cnt]?weight;
  bidmap::s!neg[cnt]?weight;
  askmap::s!neg[cnt]?weight;
  weightedsyms::skewitems[`long$weight*10;til cnt];
  sideweight::cnt?{x,cnt-x}'[1+til cnt-1];
  sidemap::s!skewitems[;side] each sideweight;
  srcweight::1+til count src;
  srcmap::s!skewitems[srcweight;] each cnt#enlist src;
  batch len;          / prime the first batch (FSP line 74)

  / connect to the tickerplant via di.servers, blocking until it is up (di.torq
  / divergence from FSP's .servers.startupdepcycles + gethandlebytype[`segmentedtickerplant])
  svc::use`di.servers;
  (svc`init)[config;deps];
  (svc`startup)[config];
  timeout:$[`waittimeout in key config;"j"$config`waittimeout;30000];
  if[not (svc`waitfortype)[`tickerplant;timeout;500];
    '"feed: no tickerplant connection within ",(string timeout),"ms - cannot start feed"];
  h::(svc`gethandlebytype)[`tickerplant;`any];

  / schedule the publish tick (di.timer divergence from FSP's .timer.repeat @ 200ms;
  / di.timer mode-1h period is whole seconds)
  period:$[`publishperiod in key config;"j"$config`publishperiod;1];
  (deps[`timer]`addjob)[`feedpublish;`.feed.feed;();period;1h;()!()];

  logdep[`info][`feed;"feed initialised (FSP port): ",(string cnt)," syms, maxn=",(string maxn),", qpt=",(string qpt),", publishing every ",(string period),"s"];
  }

\d .
