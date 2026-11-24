/ stp1: packets rows arrive with their capture time from filealerter1's processpcaps (the pcap's own
/ timestamps), so the tickerplant must not prepend its own time column as it does for trade and quote.
/ .stplg.updtab is looked up on every message, so setting it here, after the stp's init, takes effect.
.stplg.updtab[`packets]:{[x;y] x};
