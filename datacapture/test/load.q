/ publishes rate rows per second per table to stp1, in 50ms batches, for secs seconds
/ q test/load.q -rate 10000 -secs 30 [-port 5401] -q </dev/null
o:.Q.opt .z.x; rate:"J"$first o`rate; secs:"J"$first o`secs;
h:hopen`$"::",$[`port in key o;first o`port;"5401"];
n:ceiling rate%20;
s:n?`$"S",/:string til 100;
b:n?`buy`sell; p:n?100f; a:p+n?1f; q1:1+n?1000; q2:1+n?1000;
msgs:(`.u.upd;;)'[`trade`quote`orders`depth;((s;p;q1;b);(s;p;a;q1;q2);(s;til n;b;p;q1;n?`new`filled`cancelled);(s;1+n?5;p;a;q1;q2))];
ticks:0; start:.z.p; stop:start+secs*0D00:00:01;
finish:{-1 "load: target ",(string rate)," rows/s per table, achieved ",(string `long$(ticks*n)%(.z.p-start)%0D00:00:01),", ticks ",(string ticks)," of ",string secs*20;exit 0};
.z.ts:{neg[h]@/:msgs;neg[h][];ticks+:1;if[.z.p>stop;finish[]]};
\t 50
