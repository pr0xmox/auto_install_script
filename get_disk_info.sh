#!/usr/bin/env bash
# sysstats-json.sh
# Usage: ./sysstats-json.sh [interval_seconds] [device_regex]
# interval_seconds: số giây giữa 2 mẫu (mặc định 1)
# device_regex: regex để lọc disk devices (vd: "sd|nvme") - mặc định lấy tất cả hợp lệ

set -euo pipefail

INTERVAL=${1:-1}
DEV_FILTER=${2:-'.*'}

# read cpu fields into array
read_cpu() {
  awk '/^cpu /{for(i=2;i<=NF;i++) s+= $i; idle=$5; print s, idle; exit}' /proc/stat
}

# read mem: total and available (kB)
read_mem() {
  awk '/MemTotal:/ {t=$2} /MemAvailable:/ {a=$2} END{print t, a}' /proc/meminfo
}

# read diskstats: returns per-device: name read_ios read_sectors write_ios write_sectors
read_disks() {
  awk -v re="$DEV_FILTER" '
  function ok(n){ return n ~ re }
  {
    # /proc/diskstats fields: major minor name ... see kernel docs
    name=$3
    if(ok(name)) {
      reads=$4; r_sectors=$6; writes=$8; w_sectors=$10
      printf("%s %s %s %s %s\n", name, reads, r_sectors, writes, w_sectors)
    }
  }' /proc/diskstats
}

# read net: return iface rx_bytes tx_bytes (bytes)
read_net() {
  awk 'NR>2 {gsub(/:/,""); iface=$1; rx=$2; tx=$10; print iface, rx, tx}' /proc/net/dev
}

# helper to build JSON safely (numbers only used, names quoted)
# Sample readings
read -r cpu_total1 cpu_idle1 <<< "$(read_cpu)"
read -r mem_total1 mem_avail1 <<< "$(read_mem)"
read -r -a disk_lines1 <<< "$(read_disks | sed -e "s/ $//g")"
read -r -a net_lines1 <<< "$(read_net | sed -e "s/ $//g")"

sleep "$INTERVAL"

read -r cpu_total2 cpu_idle2 <<< "$(read_cpu)"
read -r mem_total2 mem_avail2 <<< "$(read_mem)"
read -r -a disk_lines2 <<< "$(read_disks | sed -e "s/ $//g")"
read -r -a net_lines2 <<< "$(read_net | sed -e "s/ $//g")"

# CPU usage percent over interval
cpu_total_diff=$((cpu_total2 - cpu_total1))
cpu_idle_diff=$((cpu_idle2 - cpu_idle1))
# avoid division by zero
if [ "$cpu_total_diff" -le 0 ]; then
  cpu_usage=0
else
  # usage = (total_diff - idle_diff) / total_diff * 100
  cpu_usage=$(awk -v t="$cpu_total_diff" -v i="$cpu_idle_diff" 'BEGIN{printf "%.2f", ((t-i)/t)*100}')
fi

# Memory
mem_total_kb=$mem_total2
mem_avail_kb=$mem_avail2
mem_used_kb=$((mem_total_kb - mem_avail_kb))
mem_used_pct=$(awk -v t="$mem_total_kb" -v u="$mem_used_kb" 'BEGIN{printf "%.2f", (u/t)*100}')

# Disk: convert sectors to kB -> assume sector = 512 bytes => kB = sectors*512/1024 = sectors/2
# Build associative arrays from lines
declare -A rsec1 rsec2 rios1 rios2 wsec1 wsec2 wios1 wios2

while read -r name reads rsectors wreads wsectors; do
  rios1["$name"]=$reads
  rsec1["$name"]=$rsectors
  wios1["$name"]=$wreads
  wsec1["$name"]=$wsectors
done < <(read_disks)

while read -r name reads rsectors wreads wsectors; do
  rios2["$name"]=$reads
  rsec2["$name"]=$rsectors
  wios2["$name"]=$wreads
  wsec2["$name"]=$wsectors
done < <(read_disks)

# Prepare disk JSON fragment
disk_json="{}"
first_disk=true
disk_json="{"
for name in "${!rsec2[@]}"; do
  # fallback zeros if not present in first
  r1=${rios1[$name]:-0}; r2=${rios2[$name]:-0}
  rs1=${rsec1[$name]:-0}; rs2=${rsec2[$name]:-0}
  w1=${wios1[$name]:-0}; w2=${wios2[$name]:-0}
  ws1=${wsec1[$name]:-0}; ws2=${wsec2[$name]:-0}

  rd_ios=$((r2 - r1))
  wr_ios=$((w2 - w1))
  rd_sectors=$((rs2 - rs1))
  wr_sectors=$((ws2 - ws1))

  # kb/s
  rd_kbs=$(awk -v s="$rd_sectors" -v iv="$INTERVAL" 'BEGIN{printf "%.2f", (s/2)/iv}')
  wr_kbs=$(awk -v s="$wr_sectors" -v iv="$INTERVAL" 'BEGIN{printf "%.2f", (s/2)/iv}')
  rd_iops=$(awk -v v="$rd_ios" -v iv="$INTERVAL" 'BEGIN{printf "%.2f", v/iv}')
  wr_iops=$(awk -v v="$wr_ios" -v iv="$INTERVAL" 'BEGIN{printf "%.2f", v/iv}')

  # append JSON entry
  if [ "$first_disk" = true ]; then first_disk=false; else disk_json+ = ","; fi
  # safer quoting for name
  esc_name=$(printf '%s' "$name" | sed 's/"/\\"/g')
  disk_json+="\"$esc_name\": {\"read_iops\": $rd_iops, \"write_iops\": $wr_iops, \"read_kB_s\": $rd_kbs, \"write_kB_s\": $wr_kbs}"
done
disk_json+="}"

# Network
declare -A rx1 tx1 rx2 tx2
while read -r iface rx tx; do
  rx1["$iface"]=$rx
  tx1["$iface"]=$tx
done < <(read_net)

# read again for second sample (we already did earlier, but reuse values)
while read -r iface rx tx; do
  rx2["$iface"]=$rx
  tx2["$iface"]=$tx
done < <(read_net)

net_json="{"
first_net=true
for iface in "${!rx2[@]}"; do
  r1=${rx1[$iface]:-0}; r2=${rx2[$iface]:-0}
  t1=${tx1[$iface]:-0}; t2=${tx2[$iface]:-0}
  dr=$((r2 - r1))
  dt=$((t2 - t1))
  dr_s=$(awk -v v="$dr" -v iv="$INTERVAL" 'BEGIN{printf "%.2f", v/iv}')
  dt_s=$(awk -v v="$dt" -v iv="$INTERVAL" 'BEGIN{printf "%.2f", v/iv}')
  if [ "$first_net" = true ]; then first_net=false; else net_json+=", "; fi
  esc_if=$(printf '%s' "$iface" | sed 's/"/\\"/g')
  net_json+="\"$esc_if\": {\"rx_B_s\": $dr_s, \"tx_B_s\": $dt_s}"
done
net_json+="}"

# Final JSON print
cat <<EOF
{
  "timestamp": $(date +%s),
  "interval_s": $INTERVAL,
  "cpu": {
    "usage_percent": $cpu_usage
  },
  "memory_kB": {
    "total": $mem_total_kb,
    "available": $mem_avail_kb,
    "used": $mem_used_kb,
    "used_percent": $mem_used_pct
  },
  "disks": $disk_json,
  "network": $net_json
}
EOF
