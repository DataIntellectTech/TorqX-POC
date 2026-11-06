/ last value cache: last traded price, current bid and current ask per sym
/ rebuilt on restart from today's trade and quote logs, so it holds only what those logs can restore

\d .lvc

empty:([sym:`u#`symbol$()]lastprice:`float$();bid:`float$();ask:`float$());
cache:empty;

/ x is a table when live and a list of columns when replayed from a log
upd:{[t;x]
  if[not 98h=type x;x:flip cols[t]!x];
  `.lvc.cache upsert $[t~`trade;select lastprice:last price by sym from x;select last bid,last ask by sym from x];
  };

/ the new day's logs hold nothing from yesterday, so a retained value could not be recovered
endofday:{[d;x] .lvc.cache:empty;};

init:{[config;deps]
  svc:deps`servers;
  (svc`startup) config;
  tpt:first config`connections;
  if[not (svc`waitfortype)[tpt;30000;500];'"lvc: no ",(string tpt)," connection within 30s"];
  (use`di.subscriptions)[`init][config;deps];
  .sub.subscribe[`trade`quote;`;1b;1b;first .sub.getsubscriptionhandles[tpt;`;()!()]];
  };

\d .

/ called by name by the tickerplant and by log replay
upd:.lvc.upd;
endofday:.lvc.endofday;
endofperiod:{[c;n;d]};
