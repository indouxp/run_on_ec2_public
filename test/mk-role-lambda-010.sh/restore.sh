#!/usr/bin/env bash
set -uo pipefail
set -eE

#
# テスト対象削除
#
rm -f config.sh
rm -f mk-role-lambda-010.sh

#
# テスト用ディレクトリへのシンボリックリンク
#
ln -s ../../src/shell/config.sh              config.sh.org                || true
ln -s ../../src/shell/mk-role-lambda-010.sh  mk-role-lambda-010.sh.org   || true
ln -s ../../src/shell/assume-role.sh         .                            || true
ln -s ../mk-vpc.sh/tc-cmn.sh                 .                            || true
