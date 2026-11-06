/ wdb1: subscribes to all four tables and is the only writer to the hdb
tickerplanttypes:`segmentedtp

/ orders and depth flush every second, which is what the idb serves; trade and quote stay out of the idb until end of day
/ ponytail: trade and quote sit in wdb memory all day as well as the rdb's
/ give them a real numtab if that gets too big, but they then show in the idb
settimer:1
numtab:`trade`quote`orders`depth!0W 0W 0 0
replaynumtab:`trade`quote!0W 0W

/ a failed ohlc must not stop the day's reload; rerun it with .ohlc.write[hdbdir;date]
postreplay:{[d;p] .[.ohlc.write;(d;p);{[e] (use`di.util.log)[`error][`ohlc;e]}]}
