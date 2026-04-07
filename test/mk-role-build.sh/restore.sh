#!/usr/bin/env bash
set -uo pipefail
set -eE

#
# テスト対象削除
#
rm -f config.sh
rm -f mk-role-build.sh

#
# テスト用ディレクトリへのシンボリックリンク
#
ln -s ../../src/shell/config.sh        config.sh.org        || true
ln -s ../../src/shell/mk-role-build.sh mk-role-build.sh.org || true
ln -s ../../src/shell/assume-role.sh   .                    || true
ln -s ../mk-vpc.sh/tc-cmn.sh           .                    || true
