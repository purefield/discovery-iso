#!/bin/bash
FACTS_FILE="/data/facts.yaml"
LOG_FILE="/data/boot-diag.log"
LOG() {
    echo "[BOOT-STEP] $1" | tee -a "$LOG_FILE"
}

gather_network_info() {
  LOG "Gathering Network Interfaces"
  echo "network_interfaces:" > "$FACTS_FILE"
  for iface in $(ls /sys/class/net); do
    echo "  - name: $iface" >> "$FACTS_FILE"
    echo "    mac_address: $(cat /sys/class/net/$iface/address)" >> "$FACTS_FILE"
    echo "    make_model: $(ethtool -i $iface 2>/dev/null | awk -F': ' '/driver|version/ {print $2}' | paste -sd ' ' -)" >> "$FACTS_FILE"
    ip addr show $iface | awk '/inet /{print "    ip_address: "$2}' >> "$FACTS_FILE"
  done
}

gather_disk_info() {
  LOG "Gathering Disk Info"
  echo "disks:" >> "$FACTS_FILE"

  for disk in $(lsblk -dno NAME,TYPE | awk '$2 == "disk" { print $1 }'); do
    path="/dev/$disk"
    model=$(cat /sys/block/$disk/device/model 2>/dev/null)
    type=$(cat /sys/block/$disk/queue/rotational | grep -q 0 && echo 'ssd' || echo 'hdd')

    LOG "$disk, $path, $model, $type"

    # Identify NVMe specifically
    if [[ "$disk" == nvme* ]]; then
      type="nvme"
    fi

    echo "  - path: $path" >> "$FACTS_FILE"
    echo "    size: $(lsblk -dn -o SIZE $path)" >> "$FACTS_FILE"
    echo "    type: $type" >> "$FACTS_FILE"
    echo "    interface: $(udevadm info --query=property --name=$path | grep ID_BUS | cut -d= -f2)" >> "$FACTS_FILE"
    echo "    model: $model" >> "$FACTS_FILE"
    echo "    serial: $(udevadm info --query=property --name=$path | grep ID_SERIAL_SHORT | cut -d= -f2)" >> "$FACTS_FILE"
    echo "    wwn: $(lsblk -Mno wwn $path)" >> "$FACTS_FILE"
  done
}

serve_data() {
  LOG "Serving data over HTTP on port 80"
  while true; do
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/yaml\r\n\r\n$(cat $FACTS_FILE)" | nc -l -p 80
  done
}

clear
LOG "Starting Host Diagnostics Script"
gather_network_info
sleep 1
gather_disk_info
sleep 1
LOG "Diagnostics Complete. Starting HTTP server..."
cat $FACTS_FILE
serve_data
