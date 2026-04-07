#!/usr/bin/env bash
set -uo pipefail
set -eE

#
# テスト対象削除
#
rm -f mk-sns-topic.sh
rm -f config.sh

#
# テスト用ディレクトリへのシンボリックリンク
#
ln -s ../../src/shell/mk-sns-topic.sh mk-sns-topic.sh.org || true
ln -s ../../src/shell/assume-role.sh .                    || true
