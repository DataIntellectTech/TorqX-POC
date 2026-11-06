/ checks .ohlc.write against a throwaway hdb. run from the app root: q test/ohlc.q
\l code/wdb/ohlc.q
db:hsym`$first system"mktemp -d";
writeday:{[d;t] (` sv .Q.par[db;d;`trade],`) set .Q.en[db] `sym`time xasc t};
day:{[d;s;p] ([]time:d+0D09+0D00:00:01*til count p;sym:(count p)#s;price:p;size:(count p)#1;side:(count p)#`buy)};
d1:2026.01.05;d2:d1+1;

writeday[d1;day[d1;`B;10 12 9 11f],day[d1;`A;5 4 6f]];
.ohlc.write[db;d1];
r:get ` sv db,`ohlc,`;
if[not `date`sym`high`low`open`close~cols r;'"columns"];
if[not (d1,d1)~r`date;'"date"];
if[not `A`B~`$string r`sym;'"sorted by sym"];
if[not 6 12f~r`high;'"high"];
if[not 4 9f~r`low;'"low"];
if[not 5 10f~r`open;'"open"];
if[not 6 11f~r`close;'"close"];

/ a second day appends; a rerun replaces rather than duplicates
writeday[d2;day[d2;`A;7 8f]];
.ohlc.write[db;d2];
.ohlc.write[db;d2];
r:get ` sv db,`ohlc,`;
if[not (d1,d1,d2)~r`date;'"second day"];
if[not 8f~last r`close;'"second day close"];

system"rm -rf ",1_string db;
-1 "ok";
exit 0
