/ compares rows the rdb received with rows in stp1's logs, per table, and the cache with the rdb
/ q test/rollcheck.q -q </dev/null    (stop the publisher first; restart lvc1 first to test recovery)
t:hopen`::5401; r:hopen`::5403; l:hopen`::5407;
n:0; upd:{[tb;x] n+:count first x};
rows:{[tb] n::0; {@[{-11!(0W;x)};last x;{-1 "replay error ",x}]} each t({.stplg.replaylog x};enlist tb); n};
c:{[tb] rr:r({count value x};tb); lr:rows tb; -1 (string tb)," rdb ",(string rr)," logs ",(string lr)," missing from logs ",string rr-lr};
c each `trade`quote;
w:(select lastprice:last price by sym from r"trade") uj select last bid,last ask by sym from r"quote";
g:l".lvc.cache";
-1 "cache syms ",(string count g)," rdb syms ",(string count w)," missing from cache ",(string count (key[w]`sym) except key[g]`sym)," cache equals rdb ",-3!(`sym xasc w)~`sym xasc g;
exit 0
