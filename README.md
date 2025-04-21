# 🔧 CoreOS Diagnostics ISO Builder

This project builds a bootable **Fedora CoreOS ISO** that:
- Runs a container on startup to collect hardware & network diagnostics.
- Serves the results as YAML over HTTP (port 80).
- Displays them on the TTY console.
- Launches `nmtui` for manual networking if needed.
- Allows shell access for advanced inspection.

---

## 📦 What It Does

- Embeds a `podman`-based container into a Fedora CoreOS ISO.
- Mounts the ISO during boot and loads the container directly.
- Gathers facts like:
  - Network interfaces
  - IP & MAC addresses
  - Disk types: `nvme`, `ssd`, `hdd` (filtered only)
- Starts an embedded HTTP server to serve `/var/facts.yaml`.

---

## 🚀 Quick Start

### 1. 🧰 Install Required Tools

You’ll need the following on your build system:

```bash
sudo dnf install podman butane genisoimage xorriso curl -y
```

### 2. 🛠 Build the ISO

```bash
chmod +x create-iso.sh
./create-iso.sh
```

This script will:
- Build the diagnostic container
- Embed Ignition into the ISO
- Inject the container image
- Rebuild the bootable ISO as `coreos-diagnostic-final.iso`

It also copies the final ISO to:
```
/var/lib/libvirt/images/coreos-diagnostic.iso
```

---

## 💻 Booting the ISO

You can boot the ISO:
- In a VM (via libvirt or virt-manager)
- On bare metal (USB/DVD)
- In PXE environments (with modifications)

On boot:
- Diagnostics are logged to `/var/boot-diag.log`
- Results are shown on the terminal
- `nmtui` is launched for manual networking
- A web server starts on **port 80** to serve `/var/facts.yaml`

### 🐚 Shell Access

After you **exit `nmtui`**, you are dropped to a shell.
From there:
- You can manually inspect logs, run commands, or test the network.
- When you **exit the shell**, the diagnostics summary will be re-displayed automatically.

---

## 🌐 Fetching Diagnostics via Web

Once the ISO has booted and networking is active:

```bash
curl http://<diagnostic-node-ip>/
```

You’ll get a clean YAML output like:

```yaml
network_interfaces:
  - name: eth0
    mac_address: aa:bb:cc:dd:ee:ff
    ip_address: 192.168.1.10/24
disks:
  - path: /dev/nvme0n1
    size: 512G
    type: nvme
    model: Samsung SSD
```

---

## 🔍 Debug Tips

- View boot logs in emergency shell:
  ```bash
  journalctl -xb
  ```
- Check if container loaded:
  ```bash
  journalctl -u container-diagnostic.service
  ```
- If the web server isn't responding, verify:
  - Network is up
  - Port 80 is not blocked
  - The container is running

---

## 📂 Files Created

| File                          | Purpose                        |
|------------------------------|--------------------------------|
| `coreos-diagnostic.oci`      | Diagnostic container image     |
| `coreos-diagnostic.iso`      | ISO with embedded Ignition     |
| `coreos-diagnostic-final.iso`| Final ISO with overlay         |
| `facts.yaml` (inside VM)     | Collected diagnostics          |
| `boot-diag.log` (inside VM)  | Boot-time logs from the script |

---

## 📝 Customization

Edit the `gather_facts.sh` section in `create-iso.sh` to add or modify:
- More hardware checks
- More metadata collection
- Output formats (e.g. JSON)

---

## 📜 License

MIT License. Use freely, modify as needed.

---

## 🙏 Acknowledgments

Built with ❤️ using:
- Fedora CoreOS
- Podman
- Butane & Ignition
- `xorriso` and `mkisofs`
