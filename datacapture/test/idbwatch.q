/ queries the idb every 100ms for secs seconds and reports errors, row counts and slow queries
/ q test/idbwatch.q -secs 60 -q </dev/null
secs:"J"$first (.Q.opt .z.x)`secs;
i:hopen`::5405;
q:"count select from orders where date=max date";
res:([]t:`timestamp$();ok:`boolean$();n:`long$();ms:`float$();err:());
stop:.z.p+secs*0D00:00:01;
while[.z.p<stop;
  s0:.z.p;
  r:@[{(1b;i x)};q;{(0b;x)}];
  `res insert (s0;r 0;$[r 0;r 1;0N];(.z.p-s0)%0D00:00:00.001;enlist $[r 0;"";r 1]);
  system"sleep 0.1"];
-1 "queries ",(string count res),", failed ",(string sum not res`ok),", slowest ms ",string `long$max res`ms;
if[any not res`ok;-1 "errors from ",(string exec first t from res where not ok)," to ",(string exec last t from res where not ok);show distinct select err from res where not ok];
g:exec n from res where ok;
-1 "row counts: first ",(string first g),", lowest ",(string min g),", last ",string last g;
d:exec first t from res where ok,n<first g;
if[not null d;-1 "count fell below start at ",(string d),", back to start at ",string exec first t from res where t>d,ok,n>=first g];
exit 0
