# 🛡️ Autonomous Security & OSINT Toolkit

[![Status: Active Development](https://img.shields.io/badge/Status-Active%20Development%20(v3.4)-brightgreen.svg)](#-project-status)
[![Organization](https://img.shields.io/badge/Organization-TwoBytesLabs-blue.svg)](https://github.com/TwoBytesLabs)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-lightgrey.svg)](#-prerequisites)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An intelligent, dual-terminal automated security research, wireless auditing, and Open Source Intelligence (OSINT) suite engineered by **Hriday Patel** under **TwoBytesLabs**.

---

## 📌 Project Status
- **Current State:** **Active Development & Operational v3.4**
- **Core Engine Status:**
  - ✅ **Dual-Terminal Multiplexing:** Fully operational on macOS and Linux (spawns synchronized scanner and live telemetry windows).
  - ✅ **Local AI Inference Engine:** Integrated with local Ollama (`http://localhost:11434`) for real-time CVE triage and service banner interpretation.
  - ✅ **Multi-Vector OSINT Engine:** Live querying for Usernames (Sherlock, Maigret), Domains (DNSTwist, Shodan, Censys), Emails (EmailRep, Paste sites), and Phone Numbers.
- **Ongoing Workflow & Roadmap:**
  - 🔄 Automated PDF & JSON executive report export.
  - 🔄 Autonomous exploit vector simulation and defensive remediation scoring.
  - 🔄 Optional Web UI / WebSocket telemetry dashboard.

---

## 🎯 What This Project Is About
Modern security audits often produce overwhelming, unstructured terminal logs. The **Autonomous Security & OSINT Toolkit** addresses this by pairing high-performance parallel network discovery with real-time AI context generation:

1. **Dual Terminal Architecture:** Separates the active raw scanning process (left terminal) from the synthesized AI telemetry and threat advisory feed (right terminal) via an ultra-fast temporary IPC bridge.
2. **Local AI Model Integration:** Interacts directly with localized Large Language Models running on your machine (via Ollama) without leaking telemetry, network fingerprints, or target queries to third-party cloud APIs.
3. **Automated Reconnaissance Pipeline:** Replaces fragmented CLI commands with an interactive, end-to-end investigative framework.

---

## 🛠️ Included Tools & Architecture

### 1. Wi-Fi Security Audit Tool (`ai_wifi_auditor.sh`)
An advanced wireless and internal subnet auditing engine with real-time AI security feedback.

```
┌────────────────────────────────┐         ┌─────────────────────────────────┐
│     LEFT TERMINAL (Engine)     │  IPC    │     RIGHT TERMINAL (AI Feed)    │
│  - Parallel Host Discovery     │ ──────> │  - Local Ollama AI Telemetry    │
│  - Port & Banner Grabbing      │ (/tmp)  │  - Real-time Threat Advisories  │
│  - Nmap, Nikto, SSLScan        │         │  - Service Vulnerability Triage │
└────────────────────────────────┘         └─────────────────────────────────┘
```

- **Parallelized Probing:** Multi-threaded host and port sweep engine utilizing `nmap -sV -O`, banner analysis, and HTTP header inspections.
- **Resource Optimized:** Fine-tuned timeouts, connection retry caps, and `nice` priority scheduling to prevent CPU thermal throttling on Apple Silicon and laptops.
- **AI-Powered Threat Interpretation:** Feeds live port banners and service signatures to Ollama to summarize potential exploitation avenues and security posture in real-time.

#### Running the Wi-Fi Auditor:
```bash
# Launch interactive dual-terminal setup (launches scanner + AI monitor):
bash ai_wifi_auditor.sh

# Run specific process components independently:
bash ai_wifi_auditor.sh --scanner    # Main scanning engine
bash ai_wifi_auditor.sh --monitor    # AI streaming feed
```

---

### 2. OSINT Lookup Tool (`OSINT.sh`)
An intelligence-gathering suite that aggregates digital footprint reconnaissance across multiple vectors into a dual-terminal display.

- **Username Reconnaissance:** Automated queries across 400+ social and developer platforms (via Sherlock & Maigret).
- **Domain & Infrastructure Footprinting:** Typosquatting checks (DNSTwist), certificate transparency, DNS enumeration, and Shodan/Censys integrations.
- **Credential & Breach Exposure:** Public paste search queries (`psbdmp.cc`), reputation analysis (`emailrep.io`), and data leak verification.
- **Phone Pattern Analysis:** TeleSpot pattern recognition and search engine index correlation.
- **Automated Dependency Bootstrap:** Built-in auto-installer utilizing `pipx`, `pip3`, and system package managers for missing tools.

#### Running the OSINT Tool:
```bash
bash OSINT.sh
```

---

## 📋 Prerequisites & Setup
- **Operating System:** macOS (Terminal / iTerm2) or Linux (Bash 4.0+)
- **System Utilities:** `nmap`, `curl`, `tput`, `git`
- **Optional (for AI Feed):** [Ollama](https://ollama.ai/) installed and running locally on port `11434`

```bash
# Clone the repository:
git clone https://github.com/TwoBytesLabs/autonomous-hacking.git
cd autonomous-hacking

# Make scripts executable:
chmod +x ai_wifi_auditor.sh OSINT.sh
```

---

## 🔒 Security & Legal Disclaimer
> [!IMPORTANT]
> This repository is maintained for authorized security research, educational exploration, defensive network hardening, and assessing systems for which the operator has explicit written consent. Unauthorized scanning, penetration testing, or reconnaissance against third-party systems without permission is strictly prohibited.

---

## 🏢 Author & Organization
- **Author:** [Hriday Patel](https://github.com/hriday-patel19)
- **Organization:** [TwoBytesLabs](https://github.com/TwoBytesLabs)
