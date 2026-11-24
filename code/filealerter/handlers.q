/ filealerter1's csv-named functions (appconfig/filealerter.csv); each takes the directory (trailing /)
/ and the file name. Loaded at root after di.torq.proc.filealerter's init; the module looks them up by name
/ at each poll. See kdbx-modules/di/torq/proc/filealerter/filealerter.md.

fa:use`di.torq.proc.filealerter;

/ a trades csv with the trade schema's columns after time (sym,price,size,stop,cond,ex,side) -> stp1;
/ the tickerplant stamps time, as it does for feed1
loadtrades:{[path;file]
  t:("SFIBCCS";enlist ",") 0: hsym `$path,file;
  fa[`sendtotickerplant][`segmentedtp;`trade;value flip t];
  };

/ a pcap 2.4 capture -> the packets table; processpcaps takes the table name as a third argument
loadpcap:{[path;file] fa[`processpcaps][path;file;`packets]};
