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
# This is now kdbx-modules, the RFC-0001 consolidation base - the whole framework resolves from
# there and the legacy TorqX checkout is no longer used at all.
#
# Honours a TORQXHOME already set in the environment, and only falls back to the sibling layout.
# That matters because the sibling checkout is a WORKING clone: whoever owns it switches branches
# and commits in it during normal development, and every such switch silently changes which module
# versions this app resolves. deps.toml then fails depcheck and EVERY process falls through to a
# bare q session - no tables, no error in the log, queries that hang rather than fail. That has
# already happened here mid-session.
#
# So for anything that must keep working across someone else's branch switches - a demo, a
# rehearsal, CI - point this at a clone pinned to a known commit:
#
#   git clone --branch <branch> --single-branch <path-or-url> ~/bin/kdbx-modules-demo
#   export TORQXHOME=~/bin/kdbx-modules-demo && source ./setenv.sh
export TORQXHOME="${TORQXHOME:-$dirpath/../kdbx-modules}"
export TORQXAPPCONFIG="$dirpath/appconfig"
# TORQXAPPHOME = the app's CODE/CONFIG root (database.q schema, code/, appconfig/, deps.toml).
# TORQXDATAHOME = where RUNTIME DATA is written/read (hdb, tplog, wdb working dir). Splitting
# them lets data live on a separate (e.g. larger/faster) volume in a real deployment; for this
# sample app they point at the same place. TorQ makes the same TORQAPPHOME/TORQDATAHOME split.
export TORQXAPPHOME="$dirpath"
export TORQXDATAHOME="$dirpath"
# TORQXSTACKID namespaces one running stack from another. torqx.sh keys BOTH its pidfile/liveness
# check and its log paths (/tmp/torqx_<stackid>_<procname>.log) on it, so two people running this
# repo on the same host under the same id collide badly: each one's `torqx.sh status` reports the
# OTHER's processes as its own, `torqx.sh stop` would kill them, and the second to start cannot
# write its logs ("Permission denied" on a file the first user owns). Suffixing the user keeps
# each stack independent on a shared box while staying a single committed default.
export TORQXSTACKID="torqx-poc-${USER}"
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

# ${QCMD:-} not $QCMD - a caller running under `set -u` (any careful script that sources this)
# aborts with "QCMD: unbound variable" on the bare form
if [ -z "${QCMD:-}" ]; then
  QCMD="q"
fi
export QCMD

alias torqx="QINIT=\$TORQXHOME/di/torq/bin/torqx_init.q \$QCMD"
