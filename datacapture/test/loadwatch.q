/ samples stp1 and subscribers while test/load.q runs, then reports a summary
/ q test/loadwatch.q -secs 30 -q </dev/null
secs:"J"$first (.Q.opt .z.x)`secs;
t:hopen`::5401; r:hopen`::5403; w:hopen`::5404; i:hopen`::5405; l:hopen`::5407;
runs:{first exec runs from t"select runs from .m.di.0timer.jobs where id=`stpzts"};
mb:{[h] (h".Q.w[]")[`heap]%1e6};
pid:900000000000;
probe:{[]
  pid+:1; s0:.z.p;
  neg[t](`.u.upd;`orders;(enlist`PROBE;enlist pid;enlist`buy;enlist 1f;enlist 1;enlist`new));neg[t][];
  q:"count select from orders where date=max date,orderid=",string pid;
  while[(0=@[i;q;0])and 60000>(.z.p-s0)%0D00:00:00.001;system"sleep 0.02"];
  (.z.p-s0)%0D00:00:00.001};
res:();
stop:.z.p+secs*0D00:00:01;
while[.z.p<stop;
  r0:runs[];t0:.z.p;
  lat:probe[];
  r1:runs[];el:(.z.p-t0)%0D00:00:00.001;
  res,:enlist `lat`msperrun`backlogmb!(lat;el%1|r1-r0;(max 0,value sum each t".z.W")%1e6);
  system"sleep 0.5"];
-1 "idb latency ms: avg ",(string `long$avg res`lat)," max ",string `long$max res`lat;
-1 "tp timer ms per run: avg ",(string .1*`long$10*avg res`msperrun)," max ",string .1*`long$10*max res`msperrun;
-1 "tp backlog MB max: ",string .1*`long$10*max res`backlogmb;
system"sleep 5";
d:t".stplg.rowcount";
-1 "tp rows trade ",(string d`trade)," orders ",string d`orders;
-1 "rdb trade ",(string r"count trade"),", wdb trade ",(string w"count trade"),", idb orders ",string i"count select from orders where date=max date";
-1 "heap MB tp ",(string `long$mb t)," rdb ",(string `long$mb r)," wdb ",(string `long$mb w)," idb ",(string `long$mb i)," lvc ",string `long$mb l;
exit 0
