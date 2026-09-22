#!/bin/bash
# Discovery failover demo: bring up a backend that is in NO phone book and no process.csv row,
# let discovery find it, then kill the primary and show queries keep working.
#
# WHY THIS IS A SCRIPT AND NOT A LIST OF STEPS IN THE README
# ---------------------------------------------------------
# di.torq.proc.gateway builds its di.serverselect routing table in registerbackends[], which runs
# ONLY at init and at EOD reload-end - never on a registry change. And registerbackends[] only
# registers rows that are CONNECTED (`not null w`). Those two facts together produce three
# separate ways to get this wrong, all of which were hit while building this script:
#
#   1. A backend discovered mid-session is connected but not routed to until a reload.
#   2. A backend that DIES mid-session leaves a dead handle in the routing table, and because
#      .gw.asyncexec passes a 0Wn timeout, a client query then BLOCKS FOREVER rather than
#      erroring. No log line, no exception - just a prompt that never returns.
#   3. THE SUBTLE ONE: reloading too EARLY is just as bad as not reloading. Discovery's push
#      lands a row as *known, not connected* (addprocs sets w:0Ni by design); the gateway then
#      dials it on di.torq.servers' own ~10s retry cycle. Reload in that gap and you rebuild the
#      routing table WITHOUT the new backend. The same applies in reverse after a kill: reload
#      before the gateway has noticed the death and you re-register the dead handle.
#
# So this script never sleeps-and-hopes. Every reload is preceded by a wait on the gateway's OWN
# registry reaching the state the reload depends on. Do not replace those waits with sleeps.
#
# If anything hangs unexpectedly during a demo, the fix is always: ./demo/gw-reload.sh
#
# Usage:  ./demo/failover.sh           run the demo
#         ./demo/failover.sh --cleanup put everything back

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source ./setenv.sh

RDB2_PORT=5308
PHONEBOOK=appconfig/nontorqprocess.csv
GWPORT=$(awk -F, '$3=="gateway"{print $2; exit}' appconfig/process.csv)
RDB1_PORT=$(awk -F, '$4=="rdb1"{print $2; exit}' appconfig/process.csv)

say(){ printf '\n\033[1m== %s\033[0m\n' "$*"; }

# probe with bash's /dev/tcp rather than ss - ss lives in /sbin, which is not reliably on PATH
# in a non-login shell
listening(){ (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && { exec 3<&-; return 0; }; return 1; }
waitport(){ local i; for i in $(seq 1 40); do listening "$1" && return 0; sleep 1; done; return 1; }

# Count rows in the GATEWAY's servers registry matching a qSQL where-clause fragment.
# NB the query MUST be sent as a string over the handle (h"...") - writing it as a bare
# expression evaluates it in this client, where .m.di.* does not exist.
gwcount(){
  timeout 15 q -q 2>/dev/null <<EOF
h:hopen\`::$GWPORT;
-1 string h"count select from .m.di.0torq.0servers.SERVERS where $1";
hclose h; exit 0;
EOF
}

# rdb1 is only useful once it has REPLAYED - the port binds, and the gateway reconnects, well
# before the trade table exists. Querying in that window returns 'trade, not a hang.
waitrdbready(){
  local i r
  for i in $(seq 1 40); do
    r=$(timeout 10 q -q 2>/dev/null <<EOF
h:hopen\`::$RDB1_PORT; -1 string h"count trade"; hclose h; exit 0;
EOF
)
    [ -n "${r:-}" ] && return 0
    sleep 2
  done
  return 1
}

waitgw(){        # wait until at least one row matches
  local i n; for i in $(seq 1 30); do n=$(gwcount "$1"); [ "${n:-0}" -ge 1 ] 2>/dev/null && return 0; sleep 2; done; return 1
}
waitgwgone(){    # wait until no row matches
  local i n; for i in $(seq 1 30); do n=$(gwcount "$1"); [ "${n:-1}" -eq 0 ] 2>/dev/null && return 0; sleep 2; done; return 1
}

# re-run registerbackends[] on the live gateway: picks up connected backends, drops dead handles
gwreload(){
  timeout 20 q -q >/dev/null 2>&1 <<EOF
h:hopen\`::$GWPORT; h(\`.gw.reload;\`reloadend); hclose h; exit 0;
EOF
  echo "   gateway routing table rebuilt"
}

query(){
  timeout 30 q -q <<EOF
h:hopen\`::$GWPORT;
neg[h](\`.gw.asyncexec;"([]pid:enlist .z.i; n:enlist count trade)";enlist\`rdb);
show h[];
hclose h; exit 0;
EOF
  [ $? -eq 124 ] && echo "   QUERY TIMED OUT - run ./demo/gw-reload.sh"
}

stoprdb2(){ local p; p=$(pgrep -u "$USER" -f 'procname rdb2'); [ -n "$p" ] && kill $p 2>/dev/null; return 0; }

if [ "${1:-}" = "--cleanup" ]; then
  say "Cleanup"
  printf 'host,port,proctype,procname\n' > "$PHONEBOOK"
  stoprdb2
  torqx.sh start rdb1 >/dev/null 2>&1
  waitport $RDB1_PORT                         || echo "   WARNING: rdb1 did not rebind $RDB1_PORT"
  waitrdbready                                || echo "   WARNING: rdb1 never finished replaying"
  waitgw "procname=\`rdb1, not null w"        || echo "   WARNING: gateway never reconnected to rdb1"
  gwreload
  echo "   verifying the gateway answers:"
  query
  torqx.sh status
  exit 0
fi

say "1. Start an rdb that is in no phone book and no process.csv row"
env -u QHOME QINIT="$TORQXHOME/di/torq/bin/torqx_init.q" nohup \
  q -torqxstackid "$TORQXSTACKID" -proctype rdb -procname rdb2 -p $RDB2_PORT \
  </dev/null >/tmp/torqx_${TORQXSTACKID}_rdb2.log 2>&1 &
if waitport $RDB2_PORT; then
  echo "   rdb2 up on $RDB2_PORT (nothing has been told about it)"
else
  echo "   rdb2 FAILED to start - see /tmp/torqx_${TORQXSTACKID}_rdb2.log"; exit 1
fi

say "2. Tell ONLY discovery about it (the gateway never reads this file)"
echo "localhost,$RDB2_PORT,rdb,rdb2" >> "$PHONEBOOK"
echo "   appended to $PHONEBOOK"

say "3. Discovery pushes it to the gateway as KNOWN; the gateway then dials it itself"
waitgw "procname=\`rdb2, not null w" || { echo "   gateway never connected to rdb2 - aborting"; exit 1; }
timeout 20 q -q <<EOF
upd:{[t;d] };
h:hopen\`::$GWPORT;
show h"select procname,proctype,connected:not null w from .m.di.0torq.0servers.SERVERS where proctype=\`rdb";
hclose h; exit 0;
EOF
echo "   connected - but still absent from the ROUTING table (log: 'registered 2 backend server(s)')"

say "4. Rebuild the routing table so rdb2 becomes selectable"
gwreload

say "5. Kill the primary, wait for the gateway to notice, then reload"
torqx.sh stop rdb1
waitgwgone "procname=\`rdb1, not null w" || echo "   WARNING: gateway still shows rdb1 connected"
gwreload

say "6. Queries keep working - answered by a process the gateway was never configured to know"
query
echo
echo "   Put everything back with:  ./demo/failover.sh --cleanup"
