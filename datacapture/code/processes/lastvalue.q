/ last traded price, current bid and ask per sym; recovered from today's trade and quote logs
\d .lastvalue

cache:([sym:`symbol$()] ltp:`float$(); bid:`float$(); ask:`float$())

init:{[config;deps]
  svc:deps`servers;
  tpt:`$first config`connections;
  (svc`startup)[config];
  if[not (svc`waitfortype)[tpt;"j"$config`tpwaittimeout;500];'"lastvalue: no ",string tpt];
  (use`di.subscriptions)[`init][config;deps];
  .sub.subscribe[`trade`quote;`;1b;1b;first .sub.getsubscriptionhandles[tpt;`;()!()]];
  deps[`log][`info][`lastvalue;"cache holds ",(string count cache)," syms after replay"];
  }

\d .

/ live updates are tables, log replay is column lists
upd:{[t;x]
  x:$[98h=type x;x;flip cols[t]!x];
  `.lastvalue.cache upsert $[t=`trade;select ltp:last price by sym from x;select last bid,last ask by sym from x];
  }

endofperiod:{[c;n;d]}
endofday:{[d;x] delete from `.lastvalue.cache}
