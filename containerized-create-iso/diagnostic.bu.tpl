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
        ExecStartPre=/usr/bin/mkdir -p /mnt/iso
        ExecStartPre=/usr/bin/mount -o ro /dev/disk/by-label/VOLID /mnt/iso
        ExecStartPre=/usr/bin/podman load -i /mnt/iso/opt/images/coreos-diagnostic.oci
        ExecStart=/usr/bin/podman run --privileged --net=host --pid=host --volume=/var:/data -w /data localhost/coreos-diagnostic
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
            ExecStart=/usr/bin/bash -c 'clear; echo "===== Welcome to CoreOS Diagnostics Boot ====="; echo "";  echo ""; echo "=== Diagnostics Output ==="; cat /var/facts.yaml 2>/dev/null || echo "(No data available yet)"; echo ""; echo "Press ENTER to open nmtui..."; read; nmtui; echo "Configure networking using setup-network.sh"; echo; exec /bin/bash'


storage:
  files:
    - path: /etc/motd
      mode: 0644
      overwrite: true
      contents:
        inline: |
          === CoreOS Diagnostics ===
          Will auto-run container + nmtui
    - path: /usr/local/bin/setup-network.sh
      mode: 775
      contents:
        source: "data:text/plain;base64,${BASE64STRING}"

passwd:
  users:
    - name: core
      groups: [wheel, sudo]
      password_hash: "*"
