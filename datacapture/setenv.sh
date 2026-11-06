#!/bin/bash
# source this for interactive use; torqx.sh sources it on every call
dirpath="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# framework checkout: kdbx-modules main at or after 2647306
export TORQXHOME="$dirpath/../../kdbx-main"
export TORQXAPPCONFIG="$dirpath/appconfig"
export TORQXAPPHOME="$dirpath"
export TORQXDATAHOME="$dirpath"
export TORQXSTACKID="datacapture-${USER}"
export KDBTPLOG="$TORQXDATAHOME/tplog"
export QPATH="$TORQXHOME:$HOME/.kx/mod"
export PATH="$TORQXHOME/di/torq/bin:$HOME/.kx/bin:$PATH"

# stp1's 50ms publish timer. Set for every process because torqx.sh reads -t as its tmux flag
export QCMD="q -t 50"

# the hdb process mounts this at startup
mkdir -p "$TORQXDATAHOME/hdb"
