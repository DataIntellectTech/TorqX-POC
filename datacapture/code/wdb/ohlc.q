/ writes date pt's high/low/open/close per sym into the hdb's top-level splayed table ohlc
.ohlc.save:{[hdb;pt]
  d:` sv hdb,`ohlc,`;
  new:0!select high:max price,low:min price,open:first price,close:last price by date:pt,sym from get ` sv .Q.par[hdb;pt;`trade],`;
  old:$[()~key d;0#new;select from get d where date<>pt];
  d set `date`sym xasc old,new;
  }
