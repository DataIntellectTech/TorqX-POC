/ simulated feed: publishes a batch to all four tables each tick; the tickerplant stamps time

\d .feed

oid:0

rnd:{0.01*floor 0.5+100*x}

tick:{
  if[null h:(svc`gethandlebytype)[tpt;`any];:()];
  px::px*1+0.001*-0.5+(count px)?1f;
  s:batch?syms;
  p:rnd px syms?s;
  neg[h](`.u.upd;`trade;(s;p;1+batch?100;batch?`buy`sell;batch?"NO"));
  neg[h](`.u.upd;`quote;(s;p-0.01;p+0.01;1+batch?100;1+batch?100;batch?"NO"));
  neg[h](`.u.upd;`orders;(s;oid+til batch;batch?`buy`sell;p;1+batch?100;batch?`new`fill`cancel));
  oid+:batch;
  neg[h](`.u.upd;`depth;(s;p-0.01;1+batch?1000;p+0.01;1+batch?1000));
  }

init:{[config;deps]
  svc::deps`servers;
  syms::`$config`syms;
  px::"f"$config`prices;
  batch::"j"$config`batch;
  tpt::`$first config`connections;
  (svc`startup)[config];
  if[not (svc`waitfortype)[tpt;"j"$config`waittimeout;500];'"feed: no ",string tpt];
  (deps[`timer]`addjob)[`feedtick;`.feed.tick;();0D00:00:00.001*"j"$config`publishms;1h;enlist[`disableonfail]!enlist 0b];
  deps[`log][`info][`feed;"publishing every ",(string config`publishms),"ms"];
  }

\d .
