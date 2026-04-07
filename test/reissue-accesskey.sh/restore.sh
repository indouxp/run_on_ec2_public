#!/usr/bin/env bash
set -uo pipefail
set -eE

rm -f reissue-accesskey.sh

ln -s ../../src/shell/reissue-accesskey.sh  reissue-accesskey.sh.org  || true
ln -s ../mk-vpc.sh/tc-cmn.sh               tc-cmn.sh                  || true
