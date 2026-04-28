---
title: System Info
---

# System Info

Updates OS, prompts hostname change, displays key info (IP, MAC, network, DNS, kernel, OS, CPU, memory, disk, load, UUID). Logs to `/var/log/sys_info.log`.

--8<-- "includes/common-header.md"
--8<-- "includes/system-requirements.md"

## Installation Command

```bash
curl -sL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/system-checks/sys-info.sh | sudo bash
```

## What It Does

- Runs preflight.
- Updates system (apt update/install deps like net-tools, curl, gpg).
- Prompts hostname change.
- Gathers/displays info.

## Verify

- Log: `cat /var/log/sys_info.log`.

- Hostname: `hostname` (changed if prompted).

- Output Example:

    ```
    📌 System Information
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     🔹 Hostname : my-lab-server
     🔹 Private IP : 192.168.1.100
     🔹 Public IP : 203.0.113.1
     🔹 MAC Address : aa:bb:cc:dd:ee:ff
     🔹 Network : 192.168.1.100/24
     🔹 DNS : 8.8.8.8, 8.8.4.4
     🔹 Kernel : 5.15.0-91-generic
     🔹 OS : Ubuntu 22.04.4 LTS
     🔹 CPU : Intel(R) Core(TM) i7-8700
     🔹 Memory : 15Gi
     🔹 Disk Usage : 20G / 100G
     🔹 CPU Load : 0.10, 0.20, 0.30
     🔹 UUID : 12345678-1234-1234-1234-123456789abc
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    ```