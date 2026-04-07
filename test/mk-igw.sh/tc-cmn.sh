################################################################################
#
# テスト環境作成共通
#
# Last updated: 2026-03-11 11:08:17
################################################################################
MY_NAME=${0##*/}
LOG_NAME=${MY_NAME}.log
LOG_DIR=.
LOG_PATH="${LOG_DIR}"/"${LOG_NAME}"
rm -f "${LOG_PATH}"

TMP_STR=$(cd ${0%/*}; pwd)
TARGET_SCRIPT="${TMP_STR##*/}"

HEADER="$(date '+%Y-%m-%d %H:%M:%S') ${USER}@$(hostname):$(pwd)"
FOOTER="$(date '+%Y-%m-%d %H:%M:%S') done."
HL="$(awk 'BEGIN{for(i=0; i<80; i++){printf("-");}printf("\n");}')"

diff_target() {
  ORG="$1"
  NOW="$2"
  echo "${HL}"
  echo "${MY_NAME}: ${NOW} オリジナルとの変更部分"
  diff ${ORG} ${NOW} && echo "変更部分はありません。"
  echo "${HL}"
}
