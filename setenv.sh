#!/bin/bash
# TorqX-POC project environment - project-owned config, not framework code.
# Source this directly for ad-hoc interactive use (defines the `torqx` alias, so you
# can run e.g. `torqx -p 5560` from anywhere once sourced), or let bin/torqx.sh source
# it automatically for orchestrated start/stop.

# ${BASH_SOURCE[0]} always resolves to this file's own path, whether it's sourced
# interactively by a human or sourced from within another script (e.g. torqx.sh) -
# unlike $0, which reflects the outermost script/shell, not the sourced file.
dirpath="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export TORQXHOME="/Users/jgrant/git/TorqX"
export TORQXAPPCONFIG="$dirpath/appconfig"
export TORQXAPPHOME="$dirpath"
export TORQXSTACKID="torqx-poc"
export QPATH="$TORQXHOME:/Users/jgrant/git/kdbx-modules"

# put torqx.sh (and any other future bin/ scripts) on PATH, so it's runnable as
# `torqx.sh ...` from the project directory instead of needing the full path. Guarded
# so re-sourcing setenv.sh (e.g. while iterating on it) doesn't keep growing PATH.
case ":$PATH:" in
  *":$TORQXHOME/bin:"*) ;;
  *) export PATH="$TORQXHOME/bin:$PATH" ;;
esac

if [ -z "$QCMD" ]; then
  QCMD="q"
fi
export QCMD

alias torqx="QINIT=\$TORQXHOME/bin/torqx_init.q \$QCMD"
