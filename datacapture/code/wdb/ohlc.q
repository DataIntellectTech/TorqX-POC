/ top-level splayed table in the hdb: high/low/open/close per date and sym, written at end of day

/ replaces pt's rows from that day's trades, so rerunning a day does not double up
.ohlc.write:{[hdb;pt]
  new:select high:max price,low:min price,open:first price,close:last price by sym from get ` sv .Q.par[hdb;pt;`trade],`;
  new:`date xcols update date:pt from 0!new;
  p:` sv hdb,`ohlc,`;
  old:$[()~key p;0#new;select from get p where date<>pt];
  p set .Q.en[hdb] `date`sym xasc old,new;
  };
