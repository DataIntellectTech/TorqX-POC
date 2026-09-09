#!/bin/bash
# TorqX-POC project environment - project-owned config, not framework code.
# Source this directly for ad-hoc interactive use (defines the `torqx` alias, so you
# can run e.g. `torqx -p 5560` from anywhere once sourced), or let bin/torqx.sh source
# it automatically for orchestrated start/stop.

# ${BASH_SOURCE[0]} always resolves to this file's own path, whether it's sourced
# interactively by a human or sourced from within another script (e.g. torqx.sh) -
# unlike $0, which reflects the outermost script/shell, not the sourced file.
dirpath="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# TORQXHOME = the FRAMEWORK checkout (its di/torq/bin launcher + di/ modules), NOT this app.
# This is now kdbx-modules (branch feature-torqx), the RFC-0001 consolidation base - the whole
# framework resolves from there and the legacy TorqX checkout is no longer used at all.
# Default assumes kdbx-modules is a sibling of this project; if it lives elsewhere, set this to
# that absolute path.
export TORQXHOME="$dirpath/../kdbx-modules"
export TORQXAPPCONFIG="$dirpath/appconfig"
# TORQXAPPHOME = the app's CODE/CONFIG root (database.q schema, code/, appconfig/, deps.toml).
# TORQXDATAHOME = where RUNTIME DATA is written/read (hdb, tplog, wdb working dir). Splitting
# them lets data live on a separate (e.g. larger/faster) volume in a real deployment; for this
# sample app they point at the same place. TorQ makes the same TORQAPPHOME/TORQDATAHOME split.
export TORQXAPPHOME="$dirpath"
export TORQXDATAHOME="$dirpath"
export TORQXSTACKID="torqx-poc"
# QPATH resolves di.* modules (colon-separated, first match wins). Everything the app needs is in
# TORQXHOME; $HOME/.kx/mod supplies the KX-shipped modules (kx.log).
export QPATH="$TORQXHOME:$HOME/.kx/mod"

# put torqx.sh (and any other future bin/ scripts) on PATH, so it's runnable as
# `torqx.sh ...` from the project directory instead of needing the full path. Guarded
# so re-sourcing setenv.sh (e.g. while iterating on it) doesn't keep growing PATH.
case ":$PATH:" in
  *":$TORQXHOME/di/torq/bin:"*) ;;
  *) export PATH="$TORQXHOME/di/torq/bin:$PATH" ;;
esac

if [ -z "$QCMD" ]; then
  QCMD="q"
fi
export QCMD

alias torqx="QINIT=\$TORQXHOME/di/torq/bin/torqx_init.q \$QCMD"
