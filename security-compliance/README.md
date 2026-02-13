# Linux Security & PCI Compliance Audit Script

## Overview

This script performs a security audit focused on detecting:

-   Malicious scripts
-   Unauthorized persistence mechanisms
-   Suspicious system services
-   Dangerous cron jobs
-   World-writable executable files
-   Suspicious running processes
-   Temporary execution abuse

It also maps findings to relevant PCI DSS controls and logs structured
results.

------------------------------------------------------------------------

## Key Features

### 1. Malicious Script Detection & Quarantine

Scans common high-risk directories:

-   `/etc`
-   `/usr/local/bin`
-   `/usr/local/sbin`
-   `/var/tmp`
-   `/dev/shm`

Detects suspicious patterns such as:

-   `eval`
-   `bash -c`
-   `base64 -d`
-   `curl | sh`
-   `wget | bash`
-   `/dev/tcp`
-   `nc -e`
-   `mkfifo`

If detected:

-   Moves the script to a quarantine directory
-   Appends a timestamp
-   Removes all permissions (`chmod 000`)
-   Logs a PCI failure event

------------------------------------------------------------------------

### 2. systemd Service Inspection

-   Enumerates all systemd services
-   Extracts `ExecStart` paths
-   Scans referenced `.sh` scripts for malicious patterns

This helps detect persistence via malicious services.

------------------------------------------------------------------------

### 3. Runtime Temporary Execution Detection

-   Identifies scripts running from:
    -   `/tmp`
    -   `/var/tmp`
    -   `/dev/shm`
-   Terminates the process (`kill -9`)
-   Quarantines the script

Helps prevent in-memory or temporary reverse shell execution.

------------------------------------------------------------------------

### 4. Suspicious Cron Job Detection

Checks:

-   `/etc/crontab`
-   `/etc/cron.d/*`

Detects:

-   `curl | sh`
-   `wget | bash`
-   `nc -e`
-   Encoded payload execution
-   External downloads from non-approved domains

Supports:

-   Cron file allowlisting
-   Approved command and domain checks
-   PCI 2.2.4 logging

------------------------------------------------------------------------

### 5. World-Writable Executable Detection

Scans the filesystem for:

-   Files that are world-writable
-   Executable by users

These are high-risk privilege escalation vectors.

Logs PCI 2.2.2 failure if found.

------------------------------------------------------------------------

### 6. Suspicious Running Process Detection

Checks for known malicious or crypto-mining indicators such as:

-   xmrig
-   minerd
-   crypto
-   botnet

Logs PCI 5.1.1 failure if detected.

------------------------------------------------------------------------

### 7. Suspicious Files in /tmp

Warns if executable scripts are found in `/tmp`, including:

-   `.sh`
-   `.py`
-   `.pl`

Temporary directories are common malware staging areas.

------------------------------------------------------------------------

## Logging & Compliance Mapping

The script integrates logging with PCI DSS controls, including:

-   PCI 5.1 -- Malware protection
-   PCI 5.1.1 -- Anti-malware mechanisms
-   PCI 5.1.2 -- Protection against malicious software
-   PCI 2.2.2 -- Secure configurations
-   PCI 2.2.4 -- Cron/service hardening

Each finding is logged as:

-   PASS
-   WARN
-   FAIL
-   INFO

------------------------------------------------------------------------

## Final Verdict Logic

If no malicious activity is found:

> PASS -- System compliant

If artifacts are detected:

> INFO -- Malicious artifacts detected and quarantined

------------------------------------------------------------------------

## Intended Use

-   Linux server hardening
-   PCI compliance validation
-   Incident response triage
-   Security baseline audits

------------------------------------------------------------------------

## Limitations

-   Pattern-based detection (can be bypassed by obfuscation)
-   May generate false positives
-   Does not inspect binaries
-   Does not analyze memory-resident malware
-   Not a replacement for EDR/antivirus

------------------------------------------------------------------------

## Recommendation

Use this script as:

-   A compliance validation tool
-   A lightweight security audit helper
-   An additional defensive layer

Not as a standalone enterprise-grade malware detection system.
