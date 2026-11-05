#!/bin/bash
# datacapture environment; torqx.sh sources this from the current directory.
dirpath="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export TORQXHOME="$dirpath/../../kdbx-modules"
export TORQXAPPHOME="$dirpath"
export TORQXAPPCONFIG="$dirpath/appconfig"
export TORQXDATAHOME="$dirpath/data"
export TORQXLOGDIR="$TORQXDATAHOME/logs"
export TORQXSTACKID="datacapture-${USER}"
export KDBTPLOG="$TORQXDATAHOME/tplog"
export QPATH="$TORQXHOME:$HOME/.kx/mod"

# -t 50 sets the segmented tickerplant's 50ms memorybatch publish
export QCMD="q -t 50"

# hdb1 mounts this at startup
mkdir -p "$TORQXDATAHOME/hdb"

case ":$PATH:" in
  *":$TORQXHOME/di/torq/bin:"*) ;;
  *) export PATH="$TORQXHOME/di/torq/bin:$PATH" ;;
esac
