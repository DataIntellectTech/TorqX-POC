/ checks the cache logic without a running stack. run from the app root: q test/lvc.q -q </dev/null
\l database.q
\l code/processes/lvc.q
c:{[msg;b] if[not b;'msg]};
p:{[t;s;px;q] ([]time:(count s)#.z.p;sym:s;price:px;size:q;side:(count s)#`buy)};

/ a live table: last row per sym wins
.lvc.upd[`trade;p[`trade;`A`B`A;10 20 11f;1 2 3]];
c["last trade";(11 20f)~exec lastprice from .lvc.cache];

/ a replayed list of columns gives the same result; a quote leaves lastprice alone
.lvc.upd[`quote;(2#.z.p;`A`A;9 10f;12 13f;1 2;3 4)];
c["quote from log";(10f;13f)~.lvc.cache[`A;`bid`ask]];
c["quote keeps lastprice";11f=.lvc.cache[`A;`lastprice]];

/ a trade leaves bid and ask alone, and a sym seen on one table has nulls for the other
.lvc.upd[`trade;p[`trade;enlist`A;enlist 12f;enlist 1]];
c["trade keeps bid";10f=.lvc.cache[`A;`bid]];
c["no quote yet";null .lvc.cache[`B;`bid]];
c["key stays unique";`u=attr key[.lvc.cache]`sym];

/ cleared at end of day, and usable after
endofday[.z.D;()!()];
c["cleared";0=count .lvc.cache];
.lvc.upd[`trade;p[`trade;enlist`A;enlist 5f;enlist 1]];
c["after clear";5f=.lvc.cache[`A;`lastprice]];
c["attr after clear";`u=attr key[.lvc.cache]`sym];

-1 "ok";
exit 0
