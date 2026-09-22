#!/bin/bash
# THE REFLEX COMMAND. If any gateway query hangs, run this.
#
# di.torq.proc.gateway refreshes its di.serverselect routing table only in registerbackends[],
# which runs at init and at EOD reload-end. So any backend that dies or restarts mid-session
# leaves a dead handle in the routing table, and .gw.asyncexec passes a 0Wn timeout - meaning a
# client query BLOCKS INDEFINITELY instead of returning an error. There is no other symptom: no
# log line, no exception at the client, just a prompt that never comes back.
#
# This re-runs registerbackends[] against the live gateway, which both drops dead handles and
# picks up any backend that has appeared since. It is idempotent and safe to run at any time.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source ./setenv.sh

GWPORT=$(awk -F, '$3=="gateway"{print $2; exit}' appconfig/process.csv)

timeout 20 q -q <<EOF
h:hopen\`::$GWPORT;
h(\`.gw.reload;\`reloadend);
-1"gateway routing table rebuilt (port $GWPORT)";
hclose h; exit 0;
EOF
[ $? -eq 124 ] && { echo "gateway itself is not responding on $GWPORT - restart it:"; echo "  torqx.sh restart gateway1"; exit 1; }
exit 0
