# Fedora Remix Lab - Quick Start Guide

This guide assumes you're using a Fedora Remix Lab ISO where the lab scripts are pre-installed.

---

## 🏗️ Initial Setup (One-Time Only)

Run these commands **once** when first setting up your lab environment:

### Step 1: Create the Lab VMs

```bash
sudo lab-create-lab-vms
```

This creates:
- **FedoraLab1** (192.168.100.10, fedoralab1.example.com)
- **FedoraLab2** (192.168.100.11, fedoralab2.example.com)
- A dedicated virtual network called **labnet**
- Pre-configured user `ansibleuser` with passwordless sudo

### Step 2: Configure Host Resolution

```bash
sudo lab-manage-hosts add
```

This adds the VM hostnames to your `/etc/hosts` file so you can reach them by name.

> **Note:** After initial setup, you only need to start the VMs when you want to use them.

---

## 🚀 Starting Your Lab

After initial setup, use this command to start your lab:

```bash
sudo lab-start-lab-vms
```

This registers and starts both VMs. Wait about 30 seconds for them to fully boot.

---

## ✅ Verify Your Lab

Check the status of your lab environment:

```bash
sudo lab-lab-status
```

You should see both VMs running with their IP addresses.

---

## 🔌 Connecting to the VMs

### Via SSH
```bash
ssh ansibleuser@fedoralab1.example.com
ssh ansibleuser@fedoralab2.example.com
```
**Password:** `Automation!`

### Via Graphical Console
```bash
sudo virt-viewer FedoraLab1
sudo virt-viewer FedoraLab2
```

---

## 📋 VM Credentials

| Setting | Value |
|---------|-------|
| Username | `ansibleuser` |
| Password | `Automation!` |
| Sudo | Passwordless (no sudo password required) |

---

## 🔧 Available Commands

### Daily Use
| Command | Description |
|---------|-------------|
| `sudo lab-start-lab-vms` | Start the lab VMs |
| `sudo lab-lab-status` | Show lab status |
| `sudo virsh shutdown FedoraLab1` | Shutdown a VM |
| `sudo virsh shutdown FedoraLab2` | Shutdown a VM |

### Initial Setup (One-Time)
| Command | Description |
|---------|-------------|
| `sudo lab-create-lab-vms` | Create VMs and network (run once) |
| `sudo lab-manage-hosts add` | Add VM entries to /etc/hosts (run once) |

### Maintenance
| Command | Description |
|---------|-------------|
| `sudo lab-reset-lab` | Destroy and recreate VMs |
| `sudo lab-manage-hosts remove` | Remove VM entries from /etc/hosts |
| `sudo lab-manage-hosts status` | Check hosts file status |

---

## 🔄 Resetting the Lab

To completely reset your lab environment:

```bash
sudo lab-reset-lab
```

Options:
- `--vms-only` - Reset only VMs, keep network
- `--full` - Reset everything (VMs + network + images)
- `--destroy-only` - Destroy without recreating

---

## 🎯 Using with Ansible

An inventory file is available at `/opt/FedoraRemixLab/inventory`:

```bash
# Test connectivity
ansible -i /opt/FedoraRemixLab/inventory nodes -m ping

# Run a command on all nodes
ansible -i /opt/FedoraRemixLab/inventory nodes -m command -a "hostname"
```

---

## 🔥 Troubleshooting

### VMs won't start

**Check if libvirtd is running:**
```bash
sudo systemctl status libvirtd
sudo systemctl start libvirtd
```

**Check if labnet network exists:**
```bash
sudo virsh net-list --all
```

If labnet is missing, recreate the VMs:
```bash
sudo lab-reset-lab
```

### Cannot connect via SSH

**Check if VMs are running:**
```bash
sudo virsh list
```

**Verify network connectivity:**
```bash
ping -c 2 192.168.100.10
ping -c 2 192.168.100.11
```

**Check hosts file:**
```bash
sudo lab-manage-hosts status
```

### Permission denied errors

All lab commands require `sudo`:
```bash
sudo lab-create-lab-vms    # Correct
lab-create-lab-vms         # Wrong - will fail
```

### virt-viewer shows blank screen

Wait 30-60 seconds after starting VMs for the boot process to complete. If still blank:
```bash
# Check if VM is actually running
sudo virsh list

# Try restarting the VM
sudo virsh reboot FedoraLab1
```

### SSH connection refused

The VM may still be booting. Wait 30 seconds and try again:
```bash
# Check if SSH port is open
nc -zv 192.168.100.10 22
```

### Reset everything and start fresh

If all else fails:
```bash
sudo lab-reset-lab --full
sudo lab-create-lab-vms
sudo lab-start-lab-vms
sudo lab-manage-hosts add
```

---

## 📁 File Locations

| Path | Description |
|------|-------------|
| `/opt/FedoraRemixLab/` | Lab scripts and files |
| `/var/lib/libvirt/images/` | VM disk images |
| `/var/lib/libvirt/images/fedora-lab/` | VM overlay images |
| `/opt/FedoraRemixLab/inventory` | Ansible inventory file |

---

## 💡 Tips

1. **Setup is one-time** - Run `lab-create-lab-vms` and `lab-manage-hosts add` only once
2. **Daily use** - Just run `sudo lab-start-lab-vms` to start your lab each session
3. **Always use sudo** - All lab commands require root privileges
4. **Wait for boot** - Give VMs 30-60 seconds to fully boot before connecting
5. **Check status first** - Use `sudo lab-lab-status` to diagnose issues
6. **Reset is your friend** - When in doubt, `sudo lab-reset-lab` fixes most problems

---

## 🆘 Getting Help

- Full documentation: `/opt/FedoraRemixLab/README.md`
- Lab status: `sudo lab-lab-status`
- Check VM console: `sudo virt-viewer FedoraLab1`

