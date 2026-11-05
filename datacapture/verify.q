/ proof queries against the running stack: q verify.q <stage> -q
/ stages: live batch latency logs check; eod1 and eod2 roll the day; sleep 25 | q verify.q cadence -q
\c 40 200
tp:hopen`::24100;hd:hopen`::24101;w:hopen`::24102;id:hopen`::24103;r:hopen`::24104;
hdr:{-1 "\n--- ",x;}
stage:`$first .z.x;
ptile:{[p;x] (asc x) floor p*-1+count x}
counts:{x"t!{count select from x}each t:tables[]"}

/ rows per table across every log of a log directory
logdir:{` sv hsym[tp".stplg.kdbtplog"],`$"stp1_",string x}
logfiles:{d:logdir x;f:key d;` sv'd,'f where not f in `stpmeta,f where f like "*segmentederror*"}
logrows:{[f]
  `rc set 0;
  `upd set {[t;x] rc::rc+count first x};
  -11!f;
  rc}
rowsinlogs:{[dt] f:logfiles dt;tn:`$-14_'5_'string last each ` vs'f;([]file:last each ` vs'f;tbl:tn;rows:logrows each f)}

live:{
  hdr "tickerplant settings";
  show `batchmode`multilog`multilogperiod`timerms!tp"(.stplg.batchmode;.stplg.multilog;.stplg.multilogperiod;system\"t\")";
  hdr "subscriber handles per table on stp1";
  show tp".stpps.subrequestall _ `";
  hdr "subscriptions held by rdb1, then wdb1";
  show r"select procname,table,active from .sub.SUBSCRIPTIONS";
  show w"select procname,table,active from .sub.SUBSCRIPTIONS";
  hdr "rdb1 tables and rows";show counts r;
  hdr "idb1 tables and rows";show counts id;
  hdr "wdb1 in-memory rows";show w"t!count each value each t:tables[]";
  hdr "hdb1 tables";show hd"tables[]";
  }

/ row sits in memory, log untouched, within one sync call; then gone from memory and in the log
batch:{
  `oid set neg 1000000+`long$.z.t;
  f:tp"exec first logname from currlog where tbl=`orders";
  hdr "one sync call on stp1: send a row, read memory and the log size";
  res:tp({[oid;f]
    s:hcount f;
    .u.upd[`orders;(enlist`BATCHTEST;enlist oid;enlist`buy;enlist 1f;enlist 1;enlist`new)];
    `rowinmemory`logsizechanged!(oid in exec orderid from orders;s<>hcount f)};oid;f);
  show res;
  `seen set 0b;
  `upd set {[t;x] if[(t=`orders) and oid in x 2;`seen set 1b]};
  hdr "immediately after, reading the log: row in log?";
  -11!f;show seen;
  system"sleep 0.1";
  hdr "100ms later: row in memory on stp1? row in log?";
  inmem:tp({x in exec orderid from orders};oid);
  -11!f;
  show `rowinmemory`rowinlog!(inmem;seen);
  }

/ publish a row every 5ms for 10s; measure batch arrival gaps at a subscriber
cadence:{
  j0:tp"exec first runs from .m.di.0timer.jobs where id=`stpzts";
  `gaps set `timestamp$();
  `upd set {[t;x] if[t=`orders;gaps,:.z.p]};
  tp(`subdetails;enlist`orders;`);
  `end set .z.p+0D00:00:10;
  `oid set -2000000;
  .z.ts:{
    if[.z.p>end;report[];exit 0];
    neg[tp](`.u.upd;`orders;(enlist`CADENCE;enlist oid-:1;enlist`buy;enlist 1f;enlist 1;enlist`new));
    };
  `report set {
    d:1_"j"$(1_deltas gaps)%1000000;
    j1:tp"exec first runs from .m.di.0timer.jobs where id=`stpzts";
    hdr "stpzts job";show tp"select id,period,mode,runs from .m.di.0timer.jobs where id=`stpzts";
    hdr "gaps between orders batches at a subscriber (ms), 200/s input";
    show `batches`min`median`p99`max!(count d;min d;ptile[.5;d];ptile[.99;d];max d);
    show `gapms xasc select batches:count i by gapms from ([]gapms:d);
    };
  system"t 5";
  }

/ send to orders and depth, poll idb1 until both are visible
latency:{
  res:{[n]
    oid:neg n+3000000+`long$.z.t;
    t0:.z.p;
    neg[tp](`.u.upd;`orders;(enlist`TRACER;enlist oid;enlist`buy;enlist 1f;enlist 1;enlist`new));
    neg[tp](`.u.upd;`depth;(enlist`TRACER;enlist 1f;enlist oid;enlist 1f;enlist 1));
    neg[tp][];
    o:d:0Nn;
    while[(null o) or null d;
      if[null o;if[count id({select from orders where date=last .Q.pv,orderid=x};oid);o:.z.p-t0]];
      if[null d;if[count id({select from depth where date=last .Q.pv,bidqty=x};oid);d:.z.p-t0]];
      if[10<(.z.p-t0)%0D00:00:01;'"not in idb after 10s"];
      system"sleep 0.02"];
    (o;d)} each til 100;
  ms:{"j"$x%1000000};
  hdr "ms from send to visible in idb1, 100 samples each";
  show flip`tbl`samples`min`median`p99`max!flip {[nm;x] (nm;count x;min x;ptile[.5;x];ptile[.99;x];max x)}'[`orders`depth;ms flip res];
  }

logs:{
  dt:tp".m.di.0eodtime.d";
  hdr "log directory ",string logdir dt;
  show key logdir dt;
  hdr ".stpm.metatable";
  show tp"select seq,logname:last each ` vs' logname,start,end,tbls,msgcount from .stpm.metatable";
  hdr "rows in each log";show rowsinlogs dt;
  }

/ the day's rows in the hdb against the tickerplant's logs
reconcile:{[dt]
  hdr "rows per table: tp logs vs hdb partition ",string dt;
  l:select logrows:sum rows by tbl from rowsinlogs[dt] where tbl in hd".Q.pt";
  p:{[dt;t] hd({[t;dt] count select from t where date=dt};t;dt)}[dt] each exec tbl from l;
  show update hdbrows:p,diff:p-logrows from l;
  }

ohlccheck:{
  hdr "hdb1 tables, and hdb/ohlc on disk";
  show hd"tables[]";
  show hd"(.Q.pt;.Q.PV;`ohlc in .Q.pt)";
  hdr "ohlc (top-level splayed; .d file)";
  show select rows:count i by date from hd"select from ohlc";
  show hd"20 sublist select from ohlc";
  hdr "matches recalculation from hdb trade?";
  a:hd"select from ohlc";
  b:hd"0!select high:max price,low:min price,open:first price,close:last price by date,sym from trade";
  show a~b;
  }

/ waits for wdb1 to finish the roll for date dt
await:{[dt]
  t0:.z.p;
  while[not dt in hd"@[value;`.Q.PV;()]";if[120<(.z.p-t0)%0D00:00:01;'"no hdb partition after 120s"];system"sleep 0.5"];
  system"sleep 3";
  }

/ end of day through the timer path: the roll is brought forward; the tick's checkends runs it
eod1:{
  dt:tp".m.di.0eodtime.d";
  hdr "before: date on stp1, hdb partitions, rdb1 rows";
  show (dt;hd"@[value;`.Q.PV;()]");show counts r;
  tp".m.di.0eodtime.nextroll:.z.p+0D00:00:02;.stplg.getnextendUTC[]";
  await dt;
  hdr "after: date on stp1, wdb1 partition, idb1 partitions, rdb1 rows";
  show (tp".m.di.0eodtime.d";w".wdb.currentpartition";id"@[value;`.Q.PV;()]");show counts r;
  hdr "rows in hdb partition";show hd({[dt] t!{[d;x] count select from x where date=d}[dt]each t:.Q.pt};dt);
  reconcile dt;
  ohlccheck[];
  }

/ end of day through the update path: an update buffered, then one arriving past the roll
eod2:{
  dt:tp".m.di.0eodtime.d";
  `oid set -4000001;
  hdr "before: date on stp1";show dt;
  tp({[oid]
    row:{(enlist`ROLLTEST;enlist x;enlist`buy;enlist 1f;enlist 1;enlist`new)};
    .u.upd[`orders;row oid];
    .m.di.0eodtime.nextroll:.z.p-0D00:00:01;
    .stplg.getnextendUTC[];
    .u.upd[`orders;row oid-1];
    };oid);
  await dt;
  hdr "buffered row ",(string oid)," in hdb partition ",string dt;
  show hd({[dt;oid] select date,sym,orderid from orders where date=dt,orderid=oid};dt;oid);
  `seen set 0;
  `upd set {[t;x] if[(t=`orders) and oid in x 2;`seen set seen+1]};
  -11!/:logfiles[dt] where logfiles[dt] like "*orders*";
  hdr "buffered row in the tp logs of ",(string dt)," (count)";show seen;
  reconcile dt;
  ohlccheck[];
  }

/ every hdb date against the logs, and ohlc; no roll
check:{reconcile each hd".Q.PV";ohlccheck[];}

@[value stage;::;{-2 "FAILED: ",x;exit 1}];
if[not stage=`cadence;exit 0];
