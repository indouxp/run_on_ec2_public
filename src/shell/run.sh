#!/bin/bash
################################################################################
# ffmpegによる変換
# システムのアクティビティをバックグラウンドで実行
# FFmpeg を Amazon Linux 2 にインストール（libx264 対応）
# ログはこのシェルを呼び出すuser_data_template.shで処理
#
# Created     : 2025-09-10
# Last updated: 2025-11-10 21:35:44
#
set -e -u -o pipefail
MY_NAME=${0##*/}

timedatectl
sudo timedatectl set-timezone Asia/Tokyo
################################################################################
# 開始メッセージ
printf "Hello from EC2!\n"
printf "Start: %s\n" $(date '+%Y-%m-%d %T.%3N')
printf "I am user: %s\n" $(whoami)
printf "My hostname is: %s\n" $(hostname -f)
lscpu
free -h
lsblk
cat /etc/system-release
cat /etc/os-release
curl -s http://169.254.169.254/latest/meta-data/instance-type
printf "\n"

################################################################################
# アクティビティ取得
cat <<EOT > /tmp/simple-act
while true; do
  echo "===== Host Activity Snapshot: \$(TZ="Asia/Tokyo" date '+%Y-%m-%d %H:%M:%S') =====";
  echo -e "\n--- Uptime / Load Average ---"; uptime;
  echo -e "\n--- Memory Usage ---"; free -h;
  echo -e "\n--- CPU Usage (mpstat) ---"; mpstat 1 1;
  echo -e "\n--- Disk I/O (iostat) ---"; iostat -xz 1 1;
  echo -e "\n--- Network Connections (ss) ---"; ss -tunap | head -n 10;
  echo -e "\n--- Logged-in Users ---"; who;
  echo -e "\n--- Top 5 CPU Processes ---"; ps aux --sort=-%cpu | head -n 6;
  echo -e "\n--- Top 5 Memory Processes ---"; ps aux --sort=-%mem | head -n 6
  sleep 10
done
EOT

bash /tmp/simple-act > simple-act.log &
PID=$!
echo "simple-act process 開始を確認"
ps -ef | grep simple-act | grep -v grep

################################################################################
# ffmepg インストール
#
cd /usr/local/bin
sudo curl -L -o ffmpeg-release-amd64-static.tar.xz https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz
sudo tar -xJf ffmpeg-release-amd64-static.tar.xz
cd ffmpeg-*
sudo cp ffmpeg /usr/local/bin/
sudo chmod +x /usr/local/bin/ffmpeg

################################################################################
# pigz インストール
#
sudo yum install -y pigz

################################################################################
# ffmpeg 実行
#
export PATH=${PATH}:/usr/local/bin
cd
echo "pigz,tar前"
ls -l

for PIGZ in "$@"; do
  pigz -dc "$PIGZ" | tar -xf -
done
#for ZIP in "$@"; do
#  unzip "$ZIP"
#done

echo "pigz,tar後"
ls -l
for MOV_PATH in *.MOV
do
  MP4=${MOV_PATH/.MOV/.mp4}
  echo $MP4
  ffmpeg -i ${MOV_PATH} ${MP4}
done

################################################################################
# kill
sleep 10 # アクティビティが低下するときのデータも取得する
kill $PID
echo "simple-act process が存在しないことを確認"
ps -ef | grep simple-act | grep -v grep || true
################################################################################
# 終了
echo "Done: $(date '+%Y-%m-%d %T.%3N')"
