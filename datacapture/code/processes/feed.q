/ simulated feed: each tick publishes a few random rows of every table; the tickerplant stamps time

\d .feed

syms:`AAPL`AMZN`GOOG`IBM`MSFT;
mid:syms!150 180 170 140 400f;
nextid:0;

rnd:{0.01*floor 0.5+100*x};

/ a table's columns, without time, for n rows
trade:{[n] s:n?syms;(s;rnd mid s;1+n?1000;n?`buy`sell)};
quote:{[n] s:n?syms;(s;rnd 0.999*mid s;rnd 1.001*mid s;1+n?1000;1+n?1000)};
orders:{[n] s:n?syms;ids:nextid+til n;nextid::nextid+n;(s;ids;n?`buy`sell;rnd mid s;1+n?1000;n?`new`filled`cancelled)};
depth:{[n] s:n?syms;l:1+n?5;(s;l;rnd mid[s]*1-0.001*l;rnd mid[s]*1+0.001*l;1+n?1000;1+n?1000)};

/ timer job: walks the prices and publishes; a tick with no tickerplant is skipped
tick:{[]
  if[null h:(svc`gethandlebytype)[tpt;`any];:()];
  mid::mid*exp 0.001*-0.5+count[syms]?1f;
  {[h;t] neg[h](`.u.upd;t;.feed[t] 1+rand 5)}[h] each `trade`quote`orders`depth;
  };

init:{[config;deps]
  svc::deps`servers;
  (svc`startup) config;
  tpt::first config`connections;
  if[not (svc`waitfortype)[tpt;30000;500];'"feed: no ",(string tpt)," connection within 30s"];
  (deps[`timer]`addjob)[`feedtick;`.feed.tick;();0D00:00:00.1;1h;(enlist`disableonfail)!enlist 0b];
  };

\d .
