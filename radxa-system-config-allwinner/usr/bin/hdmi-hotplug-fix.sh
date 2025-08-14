#!/bin/sh
# 监听到 DRM 热插拔后调用：仅当 /sys/class/hdmi/.../hdmi_source 报 "mode set = no" 才修复
# 日志：/run/hdmi-hotplug.log
exec 1>>/run/hdmi-hotplug.log 2>&1
echo "=== $(date) === hotplug start: $1"
PATH=/usr/sbin:/usr/bin:/sbin:/bin

# --- 简单去抖：3秒内的重复事件直接跳过 ---
LAST=/run/hdmi-hotplug.last
now=$(date +%s)
if [ -f "$LAST" ]; then
  last=$(cat "$LAST" 2>/dev/null || echo 0)
  [ $((now - last)) -lt 3 ] && { echo "debounce: skip"; exit 0; }
fi
echo "$now" > "$LAST"

# --- 读取 attr，判断 mode set 列 ---
ATTR=/sys/class/hdmi/hdmi/attr/hdmi_source
MODESET=$(awk -F'|' '
  /mode set/ { for(i=1;i<=NF;i++){t=$i;gsub(/^ +| +$/,"",t); if(t=="mode set") col=i } }
  /\| *state *\|/ && col { v=$col; gsub(/^ +| +$/,"",v); print v; exit }
' "$ATTR" 2>/dev/null)

[ -n "$MODESET" ] || MODESET=no  # 读不到就当未设置
echo "mode_set=$MODESET"
[ "$MODESET" = "no" ] || { echo "already modeset, skip"; exit 0; }

# --- 选择一个可用的 X cookie（优先 sddm，其次用户 .Xauthority）并快速自检 ---
XAUTH="$(ls -1t /var/run/sddm/* 2>/dev/null | head -n1)"
[ -n "$XAUTH" ] || XAUTH="$(ls -1t /home/*/.Xauthority 2>/dev/null | head -n1)"
if ! env -i PATH="$PATH" DISPLAY=:0 XAUTHORITY="$XAUTH" xrandr --query >/dev/null 2>&1; then
  echo "xrandr :0 not ready (XAUTH=$XAUTH)"; exit 0
fi

# --- 调用你已有的“二挡→auto”修复脚本（强制执行一次）---
/usr/local/bin/hdmi-toggle-once.sh force
echo "hotplug fix end"