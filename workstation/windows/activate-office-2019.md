# Office 2019 — Volume License Activation via KMS

## Context

Microsoft Office 2019 ships in a Retail edition by default. The retail license requires
online account activation, which ties the installation to a Microsoft account. Converting
the retail license to a Volume license and activating via a KMS host removes that
dependency and allows activation using a standard KMS client key.

This procedure was applied to a Windows machine where Office 2019 ProPlus Retail was
already installed from the official Microsoft ISO.

---

## What Was Done

| Step | Action |
|---|---|
| ISO obtained | Downloaded Office 2019 ProPlus Retail ISO from official Microsoft CDN |
| License converted | Retail license converted to Volume license using bundled `.xrm-ms` files |
| KMS activation | Office activated against a KMS host using the standard ProPlus 2019 VL key |

---

## Prerequisites

- Office 2019 installed (ProPlus Retail edition)
- Windows machine with internet access
- Command Prompt open with Administrator privileges

### Opening Command Prompt as Administrator

**Method 1 - Start Menu:**

1. Press the Windows key, type `cmd`.
2. Right-click **Command Prompt** in the results.
3. Select **Run as administrator** and click **Yes** on the UAC prompt.

**Method 2 - Run Dialog:**

1. Press `Win + R`, type `cmd`.
2. Press `Ctrl + Shift + Enter` instead of Enter.
3. Click **Yes** on the UAC prompt.

**Method 3 - Task Manager:**

1. Press `Ctrl + Shift + Esc` and open **File** then **Run new task**.
2. Type `cmd`, check **Create this task with administrative privileges** and click **OK**.

---

## Steps

### 1. Download the ISO

The official Office 2019 ProPlus Retail ISO is available directly from Microsoft CDN:

```text
https://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60/media/en-us/ProPlus2019Retail.img
```

### 2. Locate the Office Installation Directory

Navigate to the Office installation directory. Run both commands - one will fail depending
on the Windows architecture; the other will succeed:

```cmd
cd /d %ProgramFiles%\Microsoft Office\Office16
cd /d %ProgramFiles(x86)%\Microsoft Office\Office16
```

> **Why both?** Office 2019 installs into `Program Files` on 64-bit Windows and into
> `Program Files (x86)` on 32-bit Windows. Running both commands identifies the correct
> path without needing to check the system architecture manually.

### 3. Convert Retail License to Volume License

The `ProPlus2019VL*.xrm-ms` license files are bundled with the Office installation.
The following loop installs all matching files:

```cmd
for /f %x in ('dir /b ..\root\Licenses16\ProPlus2019VL*.xrm-ms') do cscript ospp.vbs /inslic:"..\root\Licenses16\%x"
```

> **Why is this step needed?** The retail edition ships with a retail license token.
> KMS activation only works with volume license tokens. This step installs the Volume
> license files that come bundled with Office itself - no external files are needed.

### 4. Activate via KMS

With the Volume license installed, activate Office against the KMS infrastructure:

```cmd
cscript ospp.vbs /setprt:1688
cscript ospp.vbs /unpkey:6MWKP
cscript ospp.vbs /inpkey:NMMKJ-6RK4F-KMJVX-8D9MJ-6MWKP
cscript ospp.vbs /sethst:23.226.136.46
cscript ospp.vbs /act
```

> **Command breakdown:**
> - `/setprt:1688` sets the KMS communication port (1688 is the standard KMS port)
> - `/unpkey:6MWKP` removes any existing product key ending in `6MWKP` (clears the retail key)
> - `/inpkey:NMMKJ-6RK4F-KMJVX-8D9MJ-6MWKP` installs the standard Office 2019 ProPlus VL KMS client key
> - `/sethst:23.226.136.46` sets the KMS host address
> - `/act` triggers the activation request

---

## Verification

```cmd
cscript ospp.vbs /dstatus
```

Expected output shows activation status:

```text
---Processing--------------------------
SKU ID: 85dd8b5f-eaa4-4af3-a628-cce9e77c9a03
LICENSE NAME: Office 19, Office19ProPlus2019VL_KMS_Client edition
LICENSE DESCRIPTION: Office 19, VOLUME_KMSCLIENT channel
LICENSE STATUS:  ---LICENSED---
```

`LICENSE STATUS: ---LICENSED---` confirms the activation succeeded.

If the status shows `---OOB_GRACE---` or `---UNLICENSED---`, the KMS host was not
reachable or the key was not accepted - recheck network connectivity and re-run `/act`.

---

## Key Decisions

**Official Microsoft CDN for the ISO.** The ISO download URL points directly to
`officecdn.microsoft.com` - Microsoft's own content delivery network. No third-party
source is involved.

**Volume license files are already on disk.** The `ProPlus2019VL*.xrm-ms` files ship
inside the Office installation directory. The conversion step uses files already present -
nothing is downloaded from external sources for the license conversion.
