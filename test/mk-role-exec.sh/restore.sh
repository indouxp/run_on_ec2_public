#!/usr/bin/env bash
set -uo pipefail
set -eE

#
# テスト対象削除
#
rm -f config.sh
rm -f mk-role-exec.sh

#
# テスト用ディレクトリへのシンボリックリンク
#
ln -s ../../src/shell/config.sh      config.sh.org       || true
ln -s ../../src/shell/mk-role-exec.sh mk-role-exec.sh.org || true
ln -s ../../src/shell/assume-role.sh .                   || true
ln -s ../mk-vpc.sh/tc-cmn.sh         .                   || true
