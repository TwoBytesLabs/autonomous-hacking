# Autonomous Security & OSINT Toolkit

A dual-terminal security research and automation suite built for macOS / Linux.

Developed by **Hriday Patel**.

---

## 🛠️ Tools Included

### 1. Wi-Fi Security Audit Tool (`ai_wifi_auditor.sh`)
Dual-terminal wireless network security assessment and diagnostics engine.
- **Dual Terminal Layout**: Runs the scan engine in the left terminal and an AI monitoring feed in the right terminal.
- **Parallel Host & Port Auditing**: High-performance multi-threaded scanning utilizing `nmap`, `nikto`, and `sslscan`.
- **Resource Optimized**: Runs background jobs with optimized timeouts and parallelism for efficient audits.

#### Usage:
```bash
# Launch interactive dual-terminal interface:
bash ai_wifi_auditor.sh

# Run individual components directly:
bash ai_wifi_auditor.sh --scanner    # Scan engine
bash ai_wifi_auditor.sh --monitor    # Real-time monitoring feed
```

---

### 2. OSINT Lookup Tool (`OSINT.sh`)
Comprehensive Open Source Intelligence (OSINT) investigation framework.
- **Dual Terminal Display**: Splits queries and streaming results across synchronized windows.
- **Reconnaissance Engine**: Multi-source querying for investigative research and digital footprint auditing.

#### Usage:
```bash
bash OSINT.sh
```

---

## 📋 Requirements
- **OS**: macOS or Linux
- **Shell**: Bash 4.0+
- **Recommended Utilities**: `nmap`, `curl`, `tput`

---

## ⚠️ Disclaimer
These tools are developed strictly for authorized security auditing, educational research, and defensive evaluation of networks and assets you have explicit permission to test.
