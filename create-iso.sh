# requirements
# - podman, coreos-installer, mkisofs
# - Access to quay.io, Docker Hub, or other container registry
# - jq, yq, ip, ethtool, lsblk, udevadm, etc.

# Download and verify coreos-installer binary
# Alternative alias coreos-installer='podman run --rm -v.:/data -w/data  quay.io/coreos/coreos-installer:release'
if [ ! -e coreos-installer ]; then
    curl -so coreos-installer https://mirror.openshift.com/pub/openshift-v4/clients/coreos-installer/latest/coreos-installer 
    curl -s https://mirror.openshift.com/pub/openshift-v4/clients/coreos-installer/latest/sha256sum.txt | egrep 'coreos-installer$' > sha256sum.txt
    sha256sum -c sha256sum.txt
fi
if [ ! -e fedora-coreos.live.x86_64.iso ]; then
# Download CoreOS - Live ISO from: 
# https://builds.coreos.fedoraproject.org/browser?stream=stable&arch=x86_64
    curl -o fedora-coreos.live.x86_64.iso https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/41.20250331.3.0/x86_64/fedora-coreos-41.20250331.3.0-live.x86_64.iso
fi

# Create Containerfile
cat <<'EOF'> Containerfile
FROM quay.io/fedora/fedora:latest

RUN dnf install -y ethtool lsof iproute nmap-ncat NetworkManager iputils yq util-linux && \
    mkdir -p /app && \
    dnf clean all

COPY gather_facts.sh /app/
CMD ["/app/gather_facts.sh"]
EOF

# Create Facts Gatherer
cat <<'EOF'> gather_facts.sh
#!/bin/bash

FACTS_FILE="/tmp/host_facts.yaml"

gather_network_info() {
  echo "network_interfaces:" > "$FACTS_FILE"
  for iface in $(ls /sys/class/net); do
    echo "  - name: $iface" >> "$FACTS_FILE"
    echo "    mac_address: $(cat /sys/class/net/$iface/address)" >> "$FACTS_FILE"
    echo "    make_model: $(ethtool -i $iface 2>/dev/null | awk -F': ' '/driver|version/ {print $2}' | paste -sd ' ' -)" >> "$FACTS_FILE"
    echo "    dhcp: $(nmcli device show $iface | grep -q 'IP4.DHCP4.OPTION' && echo true || echo false)" >> "$FACTS_FILE"
    ip addr show $iface | awk '/inet /{print "    ip_address: "$2}' >> "$FACTS_FILE"
  done
}

gather_disk_info() {
  echo "disks:" >> "$FACTS_FILE"
  for disk in $(lsblk -dn -o NAME); do
    path="/dev/$disk"
    echo "  - path: $path" >> "$FACTS_FILE"
    echo "    size: $(lsblk -dn -o SIZE $path)" >> "$FACTS_FILE"
    echo "    type: $(cat /sys/block/$disk/queue/rotational | grep -q 0 && echo 'ssd' || echo 'hdd')" >> "$FACTS_FILE"
    echo "    interface: $(udevadm info --query=property --name=$path | grep ID_BUS | cut -d= -f2)" >> "$FACTS_FILE"
    echo "    model: $(cat /sys/block/$disk/device/model 2>/dev/null)" >> "$FACTS_FILE"
    echo "    serial: $(udevadm info --query=property --name=$path | grep ID_SERIAL_SHORT | cut -d= -f2)" >> "$FACTS_FILE"
  done
}

serve_data() {
  while true; do
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/yaml\r\n\r\n$(cat $FACTS_FILE)" | nc -l -p 80 -q 1
  done
}

clear
gather_network_info
gather_disk_info
cat $FACTS_FILE
serve_data
EOF

# Build your diagnostic image
podman build -t coreos-diagnostic .
podman save --format oci-archive -o coreos-diagnostic.oci coreos-diagnostic

# Create overlay files
mkdir -p iso-overlay/opt/images
cp coreos-diagnostic.oci iso-overlay/opt/images/

# Create Ignition Config
cat <<'EOF'> diagnostic.bu
variant: fcos
version: 1.5.0

systemd:
  units:
    - name: container-diagnostic.service
      enabled: true
      contents: |
        [Unit]
        Description=Run diagnostic container
        After=network-online.target
        Wants=network-online.target

        [Service]
        ExecStartPre=/usr/bin/podman load -i /opt/images/coreos-diagnostic.oci
        ExecStart=/usr/bin/podman run --privileged --net=host --pid=host --volume=/:/host localhost/coreos-diagnostic
        Restart=always
        RestartSec=10

        [Install]
        WantedBy=multi-user.target

    - name: getty@tty1.service
      dropins:
        - name: override.conf
          contents: |
            [Service]
            ExecStart=
            ExecStart=/usr/bin/bash -c 'sleep 2; clear; echo "=== Host Diagnostics ==="; echo; cat /host/tmp/diagnostics.txt 2>/dev/null || echo "(data not yet available)"; echo; echo "Press ENTER to continue to nmtui..."; read; exec nmtui'

storage:
  files:
    - path: /etc/motd
      mode: 0644
      overwrite: true
      contents:
        inline: |
          === CoreOS Diagnostics ===
          Will auto-run container + nmtui

passwd:
  users:
    - name: core
      groups: [wheel, sudo]
      password_hash: "*"
EOF
# Generate Ignition config:
# podman run --rm -i quay.io/coreos/butane:release --pretty --strict < diagnostic.bu > config.ign
butane -p -o config.ign diagnostic.bu

# Embed ignirion config
rm -f coreos-diagnostic.iso
./coreos-installer iso ignition embed -i config.ign -o coreos-diagnostic.iso fedora-coreos.live.x86_64.iso
./coreos-installer iso customize --dest-iso coreos-diagnostic.iso --overlay iso-overlay

# Make discovery iso available for vm
sudo cp coreos-diagnostic.iso /var/lib/libvirt/images
