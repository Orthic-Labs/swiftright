#!/bin/sh
# usage: errs.sh <build-log>  -> deduped "file:line:col: error: msg" lines
sed 's/\x1b\[[0-9;]*m//g' "$1" | grep -E "\.swift:[0-9]+:[0-9]+: error:" | sed -E 's#^.*/(out/src|src)/##' | sort -u
