#!/bin/bash
set -e

# --- Requirements check ---
command -v podman >/dev/null || { echo "podman is required"; exit 1; }
command -v butane >/dev/null || { echo "butane is required"; exit 1; }
command -v mkisofs >/dev/null || { echo "mkisofs is required"; exit 1; }

# --- Download coreos-installer ---
if [ ! -e coreos-installer ]; then
    curl -so coreos-installer https://mirror.openshift.com/pub/openshift-v4/clients/coreos-installer/latest/coreos-installer
    curl -s https://mirror.openshift.com/pub/openshift-v4/clients/coreos-installer/latest/sha256sum.txt | grep 'coreos-installer$' > sha256sum.txt
    sha256sum -c sha256sum.txt
    chmod +x coreos-installer
fi

# --- Download Fedora CoreOS ISO ---
if [ ! -e fedora-coreos.live.x86_64.iso ]; then
    curl -o fedora-coreos.live.x86_64.iso https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/41.20250331.3.0/x86_64/fedora-coreos-41.20250331.3.0-live.x86_64.iso
fi

# --- Build diagnostic container ---
cat <<'EOF'> Containerfile
FROM quay.io/fedora/fedora:latest
RUN dnf install -y ethtool lsof iproute nmap-ncat NetworkManager iputils yq util-linux && \
    mkdir -p /app && dnf clean all
COPY gather_facts.sh /app/
CMD ["/app/gather_facts.sh"]
EOF

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

podman build -t coreos-diagnostic .
podman save --format oci-archive -o coreos-diagnostic.oci coreos-diagnostic

# --- Create Ignition config ---
mkdir -p iso-overlay/opt/images
cp coreos-diagnostic.oci iso-overlay/opt/images/

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

butane -p -o config.ign diagnostic.bu

# --- Embed Ignition config into ISO ---
cp fedora-coreos.live.x86_64.iso coreos-diagnostic.iso
./coreos-installer iso ignition embed -i config.ign coreos-diagnostic.iso

# --- Inject overlay files ---
chmod +w iso-root -R
rm -rf iso-root
mkdir -p iso-root
xorriso -osirrox on -indev coreos-diagnostic.iso -extract / iso-root
chmod +w iso-root/isolinux/isolinux.bin
cp -r iso-overlay/* iso-root/

# --- Rebuild ISO with overlay ---
mkisofs -o coreos-diagnostic-final.iso \
  -V "COREOS_DIAG" \
  -J -R -f -input-charset utf-8 \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -b isolinux/isolinux.bin -c isolinux/boot.cat \
  -eltorito-alt-boot -e images/efiboot.img -no-emul-boot \
  iso-root

# --- Make ISO available to VM ---
sudo cp coreos-diagnostic-final.iso /var/lib/libvirt/images/coreos-diagnostic.iso
