/ sends one uniquely-named sym per message to trade and quote on stp1 for secs seconds, so a row missing from a log is a sym missing after replay
/ q test/burst.q -secs 35 [-port 5401] -q </dev/null
o:.Q.opt .z.x; secs:"J"$first o`secs;
h:hopen`$"::",$[`port in key o;first o`port;"5401"];
n:0; stop:.z.p+secs*0D00:00:01;
while[.z.p<stop;
  s:enlist`$"B",string n+:1;
  neg[h](`.u.upd;`trade;(s;enlist 1f;enlist 1;enlist`buy));
  neg[h](`.u.upd;`quote;(s;enlist 1f;enlist 2f;enlist 1;enlist 1));
  neg[h][];
  system"sleep 0.002"];
-1 "sent ",(string n)," rows per table";
exit 0
