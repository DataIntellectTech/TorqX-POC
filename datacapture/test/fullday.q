/ writes a full day of hourly tickerplant logs for today into tplog, as stp1 would have, and saves the expected results
/ start from a clean stack; 864000 messages per table at 3 rows each is the feed's rate over 24 hours
/ q test/fullday.q -q </dev/null
\l database.q
d:.z.d;
dir:` sv hsym[`$getenv`KDBTPLOG],`$"stp1_",string d;
syms:`$"S",/:string til 100;
meta0:([]seq:`int$();logname:`$();start:`timestamp$();end:`timestamp$();tbls:();msgcount:`int$();schema:();additional:());
nmsg:36000; nrow:3*nmsg;
gen:{[tb;tm]
  s:nrow?syms; p:100+nrow?100f; a:p+nrow?1f; q:1+nrow?1000;
  c:$[tb~`trade;(s;p;q;nrow?`buy`sell);
      tb~`quote;(s;p;a;q;q);
      tb~`orders;(s;til nrow;nrow?`buy`sell;p;q;nrow?`new`filled`cancelled);
      (s;1+nrow?5;p;a;q;q)];
  enlist[raze 3#/:tm],c};
writefile:{[tb;hr]
  st:d+hr*0D01;
  f:` sv dir,`$"stp1_",(string tb),(string[d] except "."),(-2#"0",string hr),"0030";
  c:gen[tb;st+0D00:00:00.1*til nmsg];
  f set ();h:hopen f;
  {[h;tb;m] h enlist(`upd;tb;m)}[h;tb] each flip 3 cut/:c;
  hclose h;
  meta0,:enlist `seq`logname`start`end`tbls`msgcount`schema`additional!(`int$hr;f;st;st+0D01;enlist tb;`int$nmsg;(enlist tb)!enlist 0#value tb;()!());
  if[tb~`trade;tr,:enlist flip `time`sym`price!c 0 1 2];
  if[tb~`quote;qu,:enlist flip `time`sym`bid`ask!c 0 1 2 3];
  };
tr:();qu:();
system"mkdir -p ",1_string dir;
t0:.z.p;
{writefile[x;] each til 24} each `trade`quote`orders`depth;
(` sv dir,`stpmeta) set meta0;
tr:raze tr;qu:raze qu;
expect:`ohlc`cache!(
  0!select high:max price,low:min price,open:first price,close:last price by sym from tr;
  (select lastprice:last price by sym from tr) lj select last bid,last ask by sym from qu);
(hsym`$"tplog/fullday-expected") set expect;
-1 "wrote ",(string count meta0)," logs, ",(string count tr)," trade rows, in ",string .z.p-t0;
exit 0
