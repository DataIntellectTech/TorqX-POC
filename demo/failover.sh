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

# An rdb is only useful once it has REPLAYED - the port binds, and the gateway reconnects, well
# before the trade table exists. Querying in that window returns 'trade, not a hang. Takes the
# port, because BOTH rdbs need this: rdb2 replays the whole day's tp log at step 1, and step 6
# queries whichever rdb is now serving.
waitrdbready(){
  local i r port=$1
  for i in $(seq 1 60); do
    r=$(timeout 10 q -q 2>/dev/null <<EOF
h:hopen\`::$port; -1 string h"count trade"; hclose h; exit 0;
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

# Match this stack's id as well as the procname - a bare 'procname rdb2' pattern would also kill
# an rdb2 belonging to another TORQXSTACKID owned by the same user.
stoprdb2(){
  local p
  p=$(pgrep -u "$USER" -f "torqxstackid $TORQXSTACKID .*procname rdb2")
  [ -n "$p" ] && kill $p 2>/dev/null
  return 0
}

PHONEBOOKBAK="/tmp/torqx_${TORQXSTACKID}_phonebook.bak"

if [ "${1:-}" = "--cleanup" ]; then
  say "Cleanup"
  # restore whatever was in the phone book before the demo ran, rather than truncating it to a
  # header - it is a TRACKED file and may legitimately carry real non-TorQ rows
  if [ -f "$PHONEBOOKBAK" ]; then
    cp "$PHONEBOOKBAK" "$PHONEBOOK" && rm -f "$PHONEBOOKBAK"
    echo "   phone book restored to its pre-demo contents"
  else
    echo "   no pre-demo phone book backup found - leaving $PHONEBOOK as is"
  fi
  stoprdb2
  torqx.sh start rdb1 >/dev/null 2>&1
  waitport $RDB1_PORT                         || echo "   WARNING: rdb1 did not rebind $RDB1_PORT"
  waitrdbready $RDB1_PORT                     || echo "   WARNING: rdb1 never finished replaying"
  waitgw "procname=\`rdb1, not null w"        || echo "   WARNING: gateway never reconnected to rdb1"
  gwreload
  echo "   verifying the gateway answers:"
  query
  torqx.sh status
  exit 0
fi

say "1. Start an rdb that is in no phone book and no process.csv row"
# Refuse to start if something is ALREADY on the port. Without this, waitport below succeeds
# instantly against the foreign listener and every later step reports success while actually
# talking to someone else's process - this host routinely has 1000+ q processes on it.
if listening $RDB2_PORT; then
  echo "   port $RDB2_PORT is already in use - refusing to start rdb2."
  echo "   Either stop whatever holds it, or edit RDB2_PORT at the top of this script."
  exit 1
fi
# Launch exactly as torqx.sh does (QHOME inherited, not stripped). Verified: a nohup launch with
# QHOME set still resolves KDB-X 5 and loads di.torq. Stripping it here would put rdb2 in a
# DIFFERENT runtime environment from every other process in the stack, which is the last thing a
# failover demo should do.
QINIT="$TORQXHOME/di/torq/bin/torqx_init.q" nohup \
  $QCMD -torqxstackid "$TORQXSTACKID" -proctype rdb -procname rdb2 -p $RDB2_PORT \
  </dev/null >/tmp/torqx_${TORQXSTACKID}_rdb2.log 2>&1 &
disown
if waitport $RDB2_PORT; then
  echo "   rdb2 up on $RDB2_PORT (nothing has been told about it)"
else
  echo "   rdb2 FAILED to start - see /tmp/torqx_${TORQXSTACKID}_rdb2.log"; exit 1
fi

say "2. Tell ONLY discovery about it (the gateway never reads this file)"
cp "$PHONEBOOK" "$PHONEBOOKBAK"          # so --cleanup can restore, not truncate
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

say "4. Wait for rdb2 to finish replaying, then rebuild the routing table"
# Connected != ready. rdb2 replays the whole day's tp log before `trade` exists; failing over to
# it mid-replay returns 'trade rather than a row.
waitrdbready $RDB2_PORT || echo "   WARNING: rdb2 never finished replaying - step 6 may error"
gwreload

say "5. Kill the primary, wait for the gateway to notice, then reload"
torqx.sh stop rdb1
waitgwgone "procname=\`rdb1, not null w" || echo "   WARNING: gateway still shows rdb1 connected"
gwreload

say "6. Queries keep working - answered by a process the gateway was never configured to know"
query
echo
echo "   Put everything back with:  ./demo/failover.sh --cleanup"
