#!/usr/bin/env bash
set -uo pipefail
set -eE

#
# テスト対象削除
# 
rm config.sh
rm mk-vpc.sh

#
# テスト用ディレクトリへのシンボリックリンク
# 
ln -s ../../src/shell/config.sh config.sh.org || true
ln -s ../../src/shell/mk-vpc.sh mk-vpc.sh.org || true
ln -s ../../src/shell/assume-role.sh .        || true
