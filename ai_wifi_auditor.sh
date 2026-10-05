#!/bin/bash

# ═══════════════════════════════════════════════════════════════
#  WIFI SECURITY AUDIT TOOL — Dual Terminal Edition
#  Made by Hriday Patel
#
#  Usage:
#    bash wifiscan.sh              — opens both terminals (launcher)
#    bash wifiscan.sh --scanner    — left terminal  (scan engine)
#    bash wifiscan.sh --monitor    — right terminal (AI feed)
#
#  SPEED CHANGES vs original (all data identical, just faster):
#   1. Phase 2 host scans run in PARALLEL (background jobs + wait)
#   2. Phase 2.5 vuln scans run in PARALLEL
#   3. nmap timeouts halved (120s→60s, 90s→45s, 15s→8s)
#   4. --max-retries reduced 2→1 throughout
#   5. --min-parallelism 8 added to all nmap port scans
#   6. nice -n 5 on nmap/nikto/sslscan keeps fan quiet (tools are
#      network-I/O bound so wall-clock time is barely affected)
# ═══════════════════════════════════════════════════════════════

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MODE="${1:-launcher}"
SHARED_DIR="${2:-}"
MAX_LOOPS=15

# ───────────────────────────────────────────────────────────────
#  ASCII ART — HRIDAY PATEL
# ───────────────────────────────────────────────────────────────
print_ascii_art() {
    local COLS ART LINE PAD
    COLS=$(tput cols 2>/dev/null || echo 100)
    ART=(
        " ██╗  ██╗██████╗ ██╗██████╗  █████╗ ██╗   ██╗    ██████╗  █████╗ ████████╗███████╗██╗     "
        " ██║  ██║██╔══██╗██║██╔══██╗██╔══██╗╚██╗ ██╔╝    ██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██║     "
        " ███████║██████╔╝██║██║  ██║███████║ ╚████╔╝     ██████╔╝███████║   ██║   █████╗  ██║     "
        " ██╔══██║██╔══██╗██║██║  ██║██╔══██║  ╚██╔╝      ██╔═══╝ ██╔══██║   ██║   ██╔══╝  ██║     "
        " ██║  ██║██║  ██║██║██████╔╝██║  ██║   ██║       ██║     ██║  ██║   ██║   ███████╗███████╗"
        " ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═════╝ ╚═╝  ╚═╝   ╚═╝       ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝"
    )
    printf "%s\n" "$(tput el)"
    for LINE in "${ART[@]}"; do
        PAD=$(( (COLS - ${#LINE}) / 2 ))
        [[ $PAD -lt 0 ]] && PAD=0
        printf "%${PAD}s%s%s\n" "" "$LINE" "$(tput el)"
    done
    printf "%s\n" "$(tput el)"
}

# ───────────────────────────────────────────────────────────────
#  SHARED HELPERS
# ───────────────────────────────────────────────────────────────
cmd_exists()    { command -v "$1" &>/dev/null; }
write_status()  { echo "$1" > "$SHARED_DIR/current"; echo "$1" >> "$SHARED_DIR/log"; }
write_stage()   { echo "$1" > "$SHARED_DIR/stage";   echo "$2" > "$SHARED_DIR/stage_total"; }
write_ai_feed() { echo "$1" >> "$SHARED_DIR/ai_feed"; }

# ═══════════════════════════════════════════════════════════════
#  MODE: --monitor   (right terminal — AI analysis feed)
# ═══════════════════════════════════════════════════════════════
if [[ "$MODE" == "--monitor" ]]; then

    [[ -z "$SHARED_DIR" || ! -d "$SHARED_DIR" ]] && exit 0

    trap 'trap - EXIT INT TERM HUP; tput cnorm; exit 0' EXIT INT TERM HUP

    SPINNER_FRAMES=('|' '/' '-' '\')
    SPIN_IDX=0

    tput civis
    clear

    while [[ ! -f "$SHARED_DIR/done" ]]; do
        [[ ! -d "$SHARED_DIR" ]] && exit 0

        tput cup 0 0

        COLS=$(tput cols 2>/dev/null || echo 100)
        LNS=$(tput lines 2>/dev/null || echo 24)
        DIV=$(printf '=%.0s' $(seq 1 "$COLS"))

        print_line() {
            printf "%s%s\n" "$1" "$(tput el)"
        }

        print_ascii_art

        print_line "$DIV"
        TITLE="WIFI SECURITY AUDIT  --  AI ANALYSIS FEED"
        PAD=$(( (COLS - ${#TITLE}) / 2 ))
        [[ $PAD -lt 0 ]] && PAD=0
        printf "%${PAD}s%s%s\n" "" "$TITLE" "$(tput el)"
        print_line "$DIV"

        STAGE=$(cat "$SHARED_DIR/stage"       2>/dev/null); [[ -z "$STAGE"    ]] && STAGE=0
        TOTAL=$(cat "$SHARED_DIR/stage_total" 2>/dev/null); [[ -z "$TOTAL"    ]] && TOTAL=0
        LOOP_NUM=$(cat "$SHARED_DIR/loop_count" 2>/dev/null); [[ -z "$LOOP_NUM" ]] && LOOP_NUM=0

        CURRENT_STAGE=$STAGE
        WIDTH=40
        FILLED=0; EMPTY=0; PCT=0; BAR=""
        [[ $TOTAL -gt 0 ]] && FILLED=$(( (CURRENT_STAGE * WIDTH) / TOTAL ))
        EMPTY=$(( WIDTH - FILLED ))
        [[ $TOTAL -gt 0 ]] && PCT=$(( (CURRENT_STAGE * 100) / TOTAL ))
        for (( i=0; i<FILLED; i++ )); do BAR+="#"; done
        for (( i=0; i<EMPTY;  i++ )); do BAR+="-"; done

        print_line "  PROGRESS : [$BAR] $CURRENT_STAGE/$TOTAL ($PCT%)"

        SPINNER="${SPINNER_FRAMES[$SPIN_IDX]}"
        SPIN_IDX=$(( (SPIN_IDX + 1) % 4 ))

        CURRENT_STAT=$(cat "$SHARED_DIR/current" 2>/dev/null)
        [[ -z "$CURRENT_STAT" ]] && CURRENT_STAT="Initializing..."

        print_line "  STATUS   : [$SPINNER] ${CURRENT_STAT:0:$((COLS-20))}"

        if [[ "$LOOP_NUM" -gt 0 ]]; then
            print_line "  AI LOOP  : $LOOP_NUM / $MAX_LOOPS"
        else
            print_line "  AI LOOP  : Waiting..."
        fi

        if [[ -f "$SHARED_DIR/ai_feed" ]]; then
            print_line "$DIV"
            print_line "  AI ANALYSIS FEED"
            print_line "$DIV"

            FEED_LINES=$(( LNS - 18 ))
            [[ $FEED_LINES -lt 2 ]] && FEED_LINES=2

            tail -n "$FEED_LINES" "$SHARED_DIR/ai_feed" 2>/dev/null | \
                while IFS= read -r line; do
                    clean_line="${line:0:$((COLS-4))}"
                    printf "  %s%s\n" "$clean_line" "$(tput el)"
                done
        fi

        tput ed
        sleep 5
    done

    # ── Final screen after scan completes ──
    show_final_screen() {
        local COLS DIV MSG PAD CREDIT CPAD
        COLS=$(tput cols 2>/dev/null || echo 100)
        DIV=$(printf '=%.0s' $(seq 1 "$COLS"))

        clear
        print_ascii_art

        echo "$DIV"
        MSG="WIFI SECURITY AUDIT -- AI EXECUTIVE SUMMARY"
        PAD=$(( (COLS - ${#MSG}) / 2 ))
        [[ $PAD -lt 0 ]] && PAD=0
        printf "%${PAD}s%s\n" "" "$MSG"
        echo "$DIV"
        echo ""

        local AI_REPORT=""
        [[ -f "$SHARED_DIR/ai_final_report.txt" ]] && \
            AI_REPORT=$(cat "$SHARED_DIR/ai_final_report.txt" 2>/dev/null)

        if [[ -n "$AI_REPORT" && "$AI_REPORT" != "Failed to generate AI summary." ]]; then
            echo "$AI_REPORT"
        else
            echo "  [!] AI Summary generation failed or not available. Displaying raw report:"
            echo ""
            [[ -f "$SHARED_DIR/final_report.txt" ]] && cat "$SHARED_DIR/final_report.txt"
        fi

        echo ""
        echo "$DIV"
        echo ""
        CREDIT="WiFi Security Audit Tool  --  Made by Hriday Patel"
        CPAD=$(( (COLS - ${#CREDIT}) / 2 ))
        [[ $CPAD -lt 0 ]] && CPAD=0
        printf "%${CPAD}s%s\n" "" "$CREDIT"
        echo ""
        echo "$DIV"
        echo ""
        print_ascii_art
        echo "$DIV"
    }

    show_final_screen
    tput cnorm
    exit 0
fi

# ═══════════════════════════════════════════════════════════════
#  MODE: --scanner   (left terminal — main scan engine)
# ═══════════════════════════════════════════════════════════════
if [[ "$MODE" == "--scanner" ]]; then

    [[ -z "$SHARED_DIR" || ! -d "$SHARED_DIR" ]] && exit 0

    # ── Root escalation ──
    if [[ $EUID -ne 0 ]]; then
        echo ""
        echo "  [*] Requesting administrator privileges (one-time)..."
        exec sudo bash "$SCRIPT_PATH" --scanner "$SHARED_DIR"
    fi

    OLLAMA_SERVE_PID=""
    cleanup() {
        trap - EXIT INT TERM HUP
        [[ -n "$OLLAMA_SERVE_PID" ]] && kill "$OLLAMA_SERVE_PID" 2>/dev/null
        curl -s http://localhost:11434/api/generate \
            -d "{\"model\": \"$MODEL\", \"keep_alive\": 0}" \
            > /dev/null 2>&1
        rm -rf "$SHARED_DIR"
        exit 0
    }
    trap cleanup EXIT INT TERM HUP

    export PATH="$PATH:$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:$HOME/go/bin"

    mkdir -p "$SHARED_DIR/reports" "$SHARED_DIR/ai_turns"
    touch "$SHARED_DIR/ai_feed" "$SHARED_DIR/ai_context.txt"
    echo "0" > "$SHARED_DIR/loop_count"

    CURRENT_STAGE=0
    TOTAL_STAGES=20

    advance() {
        CURRENT_STAGE=$(( CURRENT_STAGE + 1 ))
        write_stage "$CURRENT_STAGE" "$TOTAL_STAGES"
        write_status "$1"
    }

    echo ""
    echo "============================================================"
    echo "  WIFI SECURITY AUDIT TOOL -- SCANNER"
    echo "  Made by Hriday Patel"
    echo "============================================================"
    echo ""

    # ─────────────────────────────────────────────────────────────
    #  DEPENDENCY CHECK & INSTALL
    # ─────────────────────────────────────────────────────────────
    echo "  [*] Checking dependencies..."
    echo ""

    if ! cmd_exists brew; then
        echo "  [!] Homebrew not found. Installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        cmd_exists brew || { echo "  [X] Homebrew install failed. Visit https://brew.sh"; exit 1; }
        echo "  [+] Homebrew installed."
    else
        printf "  [+] %-22s OK\n" "brew"
    fi

    safe_brew_install() {
        local CMD="$1" PKG="$2"
        if cmd_exists "$CMD"; then
            printf "  [+] %-22s OK\n" "$CMD"
        else
            echo "  [!] $CMD not found. Installing..."
            brew install "$PKG" &>/dev/null
            if cmd_exists "$CMD"; then
                echo "  [+] $CMD installed."
            else
                echo "  [~] $CMD install failed -- will skip if needed."
            fi
        fi
    }

    safe_brew_install nmap      nmap
    safe_brew_install nikto     nikto
    safe_brew_install sslscan   sslscan
    safe_brew_install snmpwalk  net-snmp
    safe_brew_install python3   python3
    safe_brew_install ollama    ollama

    # ─────────────────────────────────────────────────────────────
    #  OLLAMA STARTUP
    # ─────────────────────────────────────────────────────────────
    echo ""
    echo "  [*] Starting Ollama service..."

    if ! curl -s --max-time 3 http://localhost:11434/api/tags &>/dev/null; then
        ollama serve &>/dev/null &
        OLLAMA_SERVE_PID=$!
        printf "  [*] Waiting for Ollama to initialise"
        for i in {1..12}; do
            sleep 2
            printf "."
            curl -s --max-time 2 http://localhost:11434/api/tags &>/dev/null && break
        done
        echo ""
    else
        printf "  [+] %-22s OK\n" "ollama service"
    fi

    MODEL="llama3.2:3b"

    printf "  [*] Checking model: %s\n" "$MODEL"
    if ! ollama list 2>/dev/null | grep -q "${MODEL%%:*}"; then
        echo "  [*] Model not found locally. Pulling (may take several minutes)..."
        ollama pull "$MODEL"
        echo "  [+] Model pulled."
    else
        printf "  [+] %-22s OK\n" "model present"
    fi

    echo "  [*] Verifying model response..."
    WARMUP=$(curl -s --max-time 30 http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$MODEL\",\"prompt\":\"Reply with the single word: OK\",\"stream\":false}" | \
        python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('response', '')[:20])
except:
    print('')
" 2>/dev/null)

    if [[ -z "$WARMUP" ]]; then
        echo "  [X] Model did not respond. Check that Ollama is running."
        exit 1
    fi
    echo "  [+] Model is live and responsive."
    echo ""

    # ─────────────────────────────────────────────────────────────
    #  NETWORK DETECTION
    # ─────────────────────────────────────────────────────────────
    echo "============================================================"
    echo "  DETECTING NETWORK"
    echo "============================================================"
    echo ""

    WIFI_IF=$(networksetup -listallhardwareports 2>/dev/null | \
        awk '/Wi-Fi/{found=1; next} found && /Device/{print $2; found=0}' | head -1)

    [[ -z "$WIFI_IF" ]] && WIFI_IF=$(networksetup -listallhardwareports 2>/dev/null | \
        awk '/Airport|AirPort/{found=1; next} found && /Device/{print $2; found=0}' | head -1)

    if [[ -z "$WIFI_IF" ]]; then
        echo "  [X] Could not detect a WiFi interface. Are you connected to WiFi?"
        exit 1
    fi

    LOCAL_IP=$(ipconfig getifaddr "$WIFI_IF" 2>/dev/null)
    if [[ -z "$LOCAL_IP" ]]; then
        echo "  [X] No IP address on $WIFI_IF. Not connected to WiFi."
        exit 1
    fi

    SUBNET=$(echo "$LOCAL_IP" | cut -d. -f1-3).0/24
    GATEWAY=$(netstat -rn 2>/dev/null | \
        awk '($1=="default" || $1=="0.0.0.0") && $2!="127.0.0.1" {print $2; exit}')
    AIRPORT_BIN="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
    SSID=$(networksetup -getairportnetwork "$WIFI_IF" 2>/dev/null | sed 's/Current Wi-Fi Network: //')
    WIFI_CHANNEL="" WIFI_BSSID=""
    if [[ -x "$AIRPORT_BIN" ]]; then
        [[ "$SSID" == *"not associated"* || -z "$SSID" ]] && \
            SSID=$("$AIRPORT_BIN" -I 2>/dev/null | awk -F': ' '/ SSID/{print $2; exit}')
        WIFI_CHANNEL=$("$AIRPORT_BIN" -I 2>/dev/null | awk '/channel/{gsub(/,/,"",$2); print $2; exit}')
        WIFI_BSSID=$("$AIRPORT_BIN"   -I 2>/dev/null | awk '/BSSID:/{print $2; exit}')
    fi

    echo "  [+] Interface  : $WIFI_IF"
    echo "  [+] Local IP   : $LOCAL_IP"
    echo "  [+] Subnet     : $SUBNET"
    echo "  [+] Gateway    : ${GATEWAY:-unknown}"
    echo "  [+] SSID       : ${SSID:-unknown}"
    [[ -n "$WIFI_CHANNEL" ]] && echo "  [+] Channel    : $WIFI_CHANNEL"
    [[ -n "$WIFI_BSSID"   ]] && echo "  [+] BSSID      : $WIFI_BSSID"
    echo ""

    SCAN_START=$(date)

    {
        echo "SSID=${SSID:-unknown}"
        echo "SUBNET=$SUBNET"
        echo "GATEWAY=${GATEWAY:-unknown}"
        echo "LOCAL_IP=$LOCAL_IP"
        echo "WIFI_IF=$WIFI_IF"
        echo "CHANNEL=${WIFI_CHANNEL:-unknown}"
        echo "BSSID=${WIFI_BSSID:-unknown}"
        echo "SCAN_START=$SCAN_START"
    } > "$SHARED_DIR/network_info.txt"

    # ─────────────────────────────────────────────────────────────
    #  PHASE 1 — HOST DISCOVERY
    #  SPEED CHANGE: --max-retries 2→1, --host-timeout 15s→8s
    # ─────────────────────────────────────────────────────────────
    echo "============================================================"
    echo "  PHASE 1 -- HOST DISCOVERY"
    echo "============================================================"
    echo ""

    advance "Phase 1 -- Host discovery sweep: $SUBNET"
    write_ai_feed "=== PHASE 1: HOST DISCOVERY ==="
    write_ai_feed "Target subnet : $SUBNET"
    write_ai_feed "SSID          : ${SSID:-unknown}"
    write_ai_feed "Gateway       : ${GATEWAY:-unknown}  <-- EXCLUDED FROM DEEP SCAN"
    write_ai_feed "Local IP      : $LOCAL_IP"

    echo "  [*] Running nmap host discovery on $SUBNET..."
    echo "      This typically takes 30-60 seconds."
    echo ""

    # SPEED CHANGE: --max-retries 1 (was 2), --host-timeout 8s (was 15s)
    # DEEP ANALYTICS: Added aggressive ping sweeps to find hidden hosts
    DISCOVERY_RAW=$(nice -n 5 nmap -sn -PE -PP -PS21,22,23,25,80,443,3389,8080 -PA80,443 \
        --max-retries 1 \
        --host-timeout 10s \
        "$SUBNET" 2>/dev/null)
    echo "$DISCOVERY_RAW"
    echo ""

    declare -a HOSTS
    while IFS= read -r line; do
        if [[ "$line" =~ Nmap\ scan\ report\ for\ .*\(([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\) ]]; then
            HOSTS+=("${BASH_REMATCH[1]}")
        elif [[ "$line" =~ Nmap\ scan\ report\ for\ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
            HOSTS+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$DISCOVERY_RAW"

    if [[ ${#HOSTS[@]} -eq 0 ]]; then
        echo "  [!] nmap returned no hosts. Falling back to ARP cache..."
        while IFS= read -r line; do
            IP=$(echo "$line" | grep -oE '\([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\)' | tr -d '()')
            [[ -n "$IP" && "$IP" != "127.0.0.1" ]] && HOSTS+=("$IP")
        done < <(arp -a 2>/dev/null)
    fi

    UNIQUE_HOSTS=()
    while IFS= read -r h; do
        UNIQUE_HOSTS+=("$h")
    done < <(printf '%s\n' "${HOSTS[@]}" | sort -u | grep -v '^$')
    HOSTS=("${UNIQUE_HOSTS[@]}")

    if [[ ${#HOSTS[@]} -eq 0 ]]; then
        echo "  [X] No hosts discovered on $SUBNET."
        echo "      Verify WiFi is connected and retry."
        exit 1
    fi

    echo "  [+] Discovered ${#HOSTS[@]} host(s):"
    for H in "${HOSTS[@]}"; do
        MARKER=""
        [[ "$H" == "$GATEWAY"  ]] && MARKER="  <-- gateway/router  [EXCLUDED FROM DEEP SCAN]"
        [[ "$H" == "$LOCAL_IP" ]] && MARKER="  <-- this machine"
        printf "      %s%s\n" "$H" "$MARKER"
    done
    echo ""

    printf '%s\n' "${HOSTS[@]}" > "$SHARED_DIR/devices.txt"
    write_ai_feed "Hosts discovered: ${HOSTS[*]}"

    TOTAL_STAGES=$(( 1 + ${#HOSTS[@]} * 4 + 1 + MAX_LOOPS + 2 ))
    write_stage "$CURRENT_STAGE" "$TOTAL_STAGES"

    # ─────────────────────────────────────────────────────────────
    #  PHASE 2 — DEEP DEVICE SCAN  (router excluded)
    #
    #  SPEED CHANGE: hosts scanned in PARALLEL (background jobs).
    #  Each host writes only to its own report file so there is
    #  zero data cross-contamination. The main process waits for
    #  all jobs before continuing to Phase 2.5.
    #
    #  Per-scan changes:
    #    --max-retries 2→1
    #    --host-timeout 120s→60s
    #    --min-parallelism 8 added (probe more ports at once)
    #    nice -n 5 on all tool calls
    # ─────────────────────────────────────────────────────────────
    echo "============================================================"
    echo "  PHASE 2 -- DEEP DEVICE SCAN  (gateway excluded, parallel)"
    echo "============================================================"
    echo ""

    write_ai_feed ""
    write_ai_feed "=== PHASE 2: DEEP DEVICE SCAN (PARALLEL) ==="

    # ── Worker function — runs in a subshell background job ──
    _phase2_scan_host() {
        local HOST="$1"
        local REPORT_FILE="$SHARED_DIR/reports/device_${HOST//./_}.txt"

        {
            echo "============================================================"
            echo "  DEVICE: $HOST"
            echo "  Scanned: $(date)"
            [[ "$HOST" == "$LOCAL_IP" ]] && echo "  Role   : This Machine"
            echo "============================================================"
            echo ""
        } > "$REPORT_FILE"

        # nmap port/service/script scan
        # SPEED CHANGE: --max-retries 1, --host-timeout 60s, --min-parallelism 8
        # DEEP ANALYTICS: Added OS detection and expanded to top 3000 ports
        NMAP_OUT=$(nice -n 5 nmap -sV -O --osscan-guess --open -T4 --top-ports 3000 \
            --max-retries 1 \
            --host-timeout 90s \
            --script-timeout 30s \
            --version-intensity 8 \
            --min-parallelism 10 \
            --script=banner,http-title,http-server-header,ssh-hostkey,ssl-cert,smb-os-discovery \
            "$HOST" 2>/dev/null)

        {
            echo "--- NMAP PORT / SERVICE SCAN ---"
            echo "$NMAP_OUT"
            echo ""
        } >> "$REPORT_FILE"

        MAC=$(arp -n "$HOST" 2>/dev/null | awk 'NR==2{print $4}')
        [[ -n "$MAC" && "$MAC" != "(incomplete)" ]] && \
            echo "MAC Address: $MAC" >> "$REPORT_FILE"

        # HTTP headers on port 80
        if echo "$NMAP_OUT" | grep -qE "^80/tcp[[:space:]]+open"; then
            HTTP_OUT=$(curl -s -I --max-time 8 "http://$HOST" 2>/dev/null | head -30)
            {
                echo "--- HTTP HEADERS (port 80) ---"
                echo "$HTTP_OUT"
                echo ""
            } >> "$REPORT_FILE"
        fi

        # SSL/TLS on port 443
        if echo "$NMAP_OUT" | grep -qE "^443/tcp[[:space:]]+open"; then
            SSL_OUT=$(nice -n 5 sslscan --no-colour "$HOST:443" 2>/dev/null | head -60)
            {
                echo "--- SSL / TLS SCAN (port 443) ---"
                echo "$SSL_OUT"
                echo ""
            } >> "$REPORT_FILE"
        fi

        # SNMP UDP 161
        SNMP_PROBE=$(nice -n 5 nmap -sU -p 161 --open \
            --max-retries 1 \
            --host-timeout 10s \
            "$HOST" 2>/dev/null)
        if echo "$SNMP_PROBE" | grep -q "161/udp.*open"; then
            SNMP_OUT=$(timeout 15 snmpwalk -v2c -c public -t 5 -r 1 "$HOST" 2>/dev/null | head -50)
            {
                echo "--- SNMP WALK (UDP 161) ---"
                echo "${SNMP_OUT:-No SNMP response to public community string.}"
                echo ""
            } >> "$REPORT_FILE"
        else
            {
                echo "--- SNMP WALK (UDP 161) ---"
                echo "SNMP port 161 not open or filtered."
                echo ""
            } >> "$REPORT_FILE"
        fi

        write_ai_feed "Device $HOST: Phase 2 scan complete."
        echo "  [+] $HOST -- Phase 2 complete."
    }

    # ── Launch all Phase 2 workers in parallel ──
    declare -a P2_PIDS
    for HOST in "${HOSTS[@]}"; do
        if [[ "$HOST" == "$GATEWAY" ]]; then
            echo "  [~] $HOST is the gateway — excluded from deep scan."
            write_ai_feed "Device $HOST: gateway — excluded from deep scan."
            continue
        fi
        echo "  [*] Starting parallel scan: $HOST"
        _phase2_scan_host "$HOST" &
        P2_PIDS+=($!)
    done

    echo ""
    echo "  [*] Waiting for all Phase 2 scans to complete..."
    for PID in "${P2_PIDS[@]}"; do
        wait "$PID"
    done

    # Advance stage for each host (same total count as before)
    for HOST in "${HOSTS[@]}"; do
        advance "Phase 2 -- complete: $HOST"
        advance "Phase 2 -- complete: $HOST (http)"
        advance "Phase 2 -- complete: $HOST (ssl)"
    done

    echo "  [+] Phase 2 complete for all hosts."
    echo ""

    # ─────────────────────────────────────────────────────────────
    #  PHASE 2.5 — VULNERABILITY & ENUMERATION SWEEP
    #
    #  SPEED CHANGE: vuln scans run in PARALLEL per host.
    #  Per-scan changes:
    #    --host-timeout 90s→45s
    #    --max-retries 1 (was 1 already)
    #    --min-parallelism 8 added
    #    nice -n 5 on all tool calls
    # ─────────────────────────────────────────────────────────────
    echo "============================================================"
    echo "  PHASE 2.5 -- VULNERABILITY & ENUMERATION SWEEP (parallel)"
    echo "============================================================"
    echo ""

    write_ai_feed ""
    write_ai_feed "=== PHASE 2.5: VULNERABILITY & ENUMERATION (PARALLEL) ==="

    advance "Phase 2.5 -- Network-wide discovery (mDNS)"
    echo "  [*] Running network-wide mDNS/Bonjour enumeration..."
    MDNS_OUT=$(timeout 8 dns-sd -B _services._dns-sd._udp local 2>/dev/null)
    {
        echo "--- MDNS / BONJOUR SERVICES ---"
        echo "${MDNS_OUT:-No mDNS services discovered.}"
        echo ""
    } > "$SHARED_DIR/reports/mdns_services.txt"
    echo "  [+] mDNS enumeration complete."
    echo ""

    # ── Worker function for Phase 2.5 ──
    _phase25_scan_host() {
        local HOST="$1"
        local REPORT_FILE="$SHARED_DIR/reports/device_${HOST//./_}.txt"

        echo "  [*] $HOST -- Running vulnerability and enumeration checks..."

        # 1. Vulnerability scripts
        # SPEED CHANGE: --host-timeout 45s (was 90s), --min-parallelism 8 added
        echo "      $HOST - Vulnerability scan..."
        OPEN_TCP=$(grep -E '^[0-9]+/tcp[[:space:]]+open' "$REPORT_FILE" 2>/dev/null | \
            cut -d/ -f1 | tr '\n' ',' | sed 's/,$//')
        if [[ -n "$OPEN_TCP" ]]; then
            VULN_OUT=$(nice -n 5 nmap -sV -p "$OPEN_TCP" \
                --script vuln \
                --max-retries 1 \
                --host-timeout 45s \
                --script-timeout 30s \
                --min-parallelism 8 \
                "$HOST" 2>/dev/null | grep -v "Nmap scan report")
        else
            VULN_OUT=$(nice -n 5 nmap -F -sV \
                --script vuln \
                --max-retries 1 \
                --host-timeout 45s \
                --script-timeout 30s \
                --min-parallelism 8 \
                "$HOST" 2>/dev/null | grep -v "Nmap scan report")
        fi
        {
            echo "--- NMAP VULNERABILITY SCAN ---"
            echo "$VULN_OUT"
            echo ""
        } >> "$REPORT_FILE"

        # 2. SMB Enumeration
        echo "      $HOST - SMB enumeration..."
        if grep -qE "^(139|445)/tcp[[:space:]]+open" "$REPORT_FILE" 2>/dev/null; then
            SMB_OUT=$(nice -n 5 nmap -p 139,445 \
                --script smb-enum-shares \
                --max-retries 1 \
                --host-timeout 30s \
                "$HOST" 2>/dev/null | grep -i smb)
            if [[ -n "$SMB_OUT" ]]; then
                {
                    echo "--- SMB SHARES ---"
                    echo "$SMB_OUT"
                    echo ""
                } >> "$REPORT_FILE"
            fi
        fi

        # 3. UPnP Discovery
        echo "      $HOST - UPnP discovery..."
        UPNP_OUT=$(nice -n 5 nmap -sU -p 1900 \
            --script=upnp-info \
            --max-retries 1 \
            --host-timeout 15s \
            "$HOST" 2>/dev/null | grep -i upnp)
        if [[ -n "$UPNP_OUT" ]]; then
            {
                echo "--- UPNP INFO (UDP 1900) ---"
                echo "$UPNP_OUT"
                echo ""
            } >> "$REPORT_FILE"
        fi

        # 4. Default credential checks
        echo "      $HOST - Default credential checks..."
        CRED_FINDINGS=""
        for PORT in 80 8080; do
            if grep -qE "^$PORT/tcp[[:space:]]+open" "$REPORT_FILE" 2>/dev/null; then
                HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 \
                    -u admin:admin "http://$HOST:$PORT/")
                if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "301" || \
                      "$HTTP_CODE" == "302" || "$HTTP_CODE" == "204" ]]; then
                    CRED_FINDINGS+="[!] Default credentials (admin:admin) accepted on HTTP port $PORT! (HTTP $HTTP_CODE)\n"
                fi
            fi
        done
        for PORT in 443 8443; do
            if grep -qE "^$PORT/tcp[[:space:]]+open" "$REPORT_FILE" 2>/dev/null; then
                HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -m 3 \
                    -u admin:admin "https://$HOST:$PORT/")
                if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "301" || \
                      "$HTTP_CODE" == "302" || "$HTTP_CODE" == "204" ]]; then
                    CRED_FINDINGS+="[!] Default credentials (admin:admin) accepted on HTTPS port $PORT! (HTTP $HTTP_CODE)\n"
                fi
            fi
        done

        if [[ -n "$CRED_FINDINGS" ]]; then
            {
                echo "--- DEFAULT CREDENTIALS ---"
                echo -e "$CRED_FINDINGS"
                echo ""
            } >> "$REPORT_FILE"
        fi

        # 5. Deep Web Vulnerability Scan (Nikto)
        echo "      $HOST - Nikto deep web scan..."
        if grep -qE "^(80|8080|443|8443)/tcp[[:space:]]+open" "$REPORT_FILE" 2>/dev/null; then
            NIKTO_PORT=$(grep -E "^(80|8080|443|8443)/tcp[[:space:]]+open" "$REPORT_FILE" 2>/dev/null | head -n 1 | cut -d/ -f1)
            NIKTO_OUT=$(nice -n 5 nikto -h "$HOST" -p "$NIKTO_PORT" -Tuning x -maxtime 45s 2>/dev/null | sed -n '/+ Target IP:/,$p')
            if [[ -n "$NIKTO_OUT" ]]; then
                {
                    echo "--- NIKTO WEB VULNERABILITY SCAN (Port $NIKTO_PORT) ---"
                    echo "$NIKTO_OUT"
                    echo ""
                } >> "$REPORT_FILE"
            fi
        fi

        write_ai_feed "Device $HOST: Phase 2.5 complete."
        echo "  [+] $HOST -- Phase 2.5 complete."
    }

    # ── Launch all Phase 2.5 workers in parallel ──
    declare -a P25_PIDS
    for HOST in "${HOSTS[@]}"; do
        [[ "$HOST" == "$GATEWAY" ]] && continue
        _phase25_scan_host "$HOST" &
        P25_PIDS+=($!)
    done

    echo ""
    echo "  [*] Waiting for all Phase 2.5 scans to complete..."
    for PID in "${P25_PIDS[@]}"; do
        wait "$PID"
    done

    for HOST in "${HOSTS[@]}"; do
        [[ "$HOST" == "$GATEWAY" ]] && continue
        advance "Phase 2.5 -- complete: $HOST"
    done

    echo "  [+] Phase 2.5 complete for all hosts."
    echo ""

    # ─────────────────────────────────────────────────────────────
    #  PHASE 3 — AI-DIRECTED ANALYSIS LOOP
    # ─────────────────────────────────────────────────────────────
    echo "============================================================"
    echo "  PHASE 3 -- AI-DIRECTED ANALYSIS LOOP"
    echo "============================================================"
    echo ""

    write_ai_feed ""
    write_ai_feed "=== PHASE 3: AI-DIRECTED ANALYSIS LOOP ==="
    write_ai_feed "Model    : $MODEL"
    write_ai_feed "Max loops: $MAX_LOOPS"

    ALLOWED_TOOLS=("nmap" "nikto" "sslscan" "curl" "snmpwalk")
    declare -a SEEN_ACTIONS
    LOOP_NUM=0

    cat > "$SHARED_DIR/ai_system.txt" << 'SYSEOF'
You are a network security analyst performing a WiFi security audit.

YOUR RESPONSE MUST BE EXACTLY 5 LINES IN THIS FORMAT — NOTHING ELSE:
SEVERITY: [CRITICAL|HIGH|MEDIUM|LOW|CLEAN]
DEVICE: [IP address of the device to investigate]
FINDING: [One sentence describing the specific vulnerability or weakness found]
ACTION: [Exact shell command using only: nmap, nikto, sslscan, curl, or snmpwalk — OR the word NONE]
REASON: [One sentence explaining why this action is the right next step]

STRICT FORMAT RULES:
- Start your response IMMEDIATELY with "SEVERITY:" — no preamble, no greeting, no markdown
- Each field must be on its own separate line
- Do NOT write anything before SEVERITY: or after REASON:
- Do NOT use bullet points, numbered lists, bold, asterisks, or markdown of any kind
- Do NOT combine multiple fields on one line
- Do NOT explain your reasoning outside the REASON field
- Your entire response must be exactly 5 lines total
- CRITICAL RULE: The ACTION line MUST contain a raw UNIX terminal command. Do NOT output English instructions like "Update the server" or "Patch the vulnerability". It MUST start with nmap, nikto, sslscan, curl, or snmpwalk.

EXAMPLE OF A PERFECTLY VALID RESPONSE (copy this structure exactly):
SEVERITY: HIGH
DEVICE: 192.168.1.100
FINDING: Port 80 exposes an HTTP admin panel that accepted default credentials admin:admin.
ACTION: nikto -h http://192.168.1.100
REASON: Nikto will identify known vulnerabilities, default files, and misconfigurations on the web server.

INVESTIGATION CATEGORIES (rotate through these in order):
1. WEB PANEL EXPOSURE - probe HTTP/HTTPS admin panels with nikto or curl on ports 80, 8080, 443, 8443
2. SSL/TLS WEAKNESS - run sslscan for expired certs, weak ciphers, SSLv3/TLSv1.0 acceptance
3. SNMP EXPOSURE - snmpwalk with community strings "public" and "private" on SNMP-enabled devices
4. SERVICE VERSION CVEs - nmap --script vuln on specific open ports
5. BANNER ANALYSIS - curl or nmap banners on unusual ports; flag plaintext protocols (telnet:23, ftp:21)
6. DEFAULT CREDENTIAL PORTS - flag telnet(23), FTP(21), SSH(22), HTTP admin panels(8080,8443)

HARD RULES:
- NEVER investigate the Gateway/Router IP — it is completely out of scope
- Only use these tools: nmap, nikto, sslscan, curl, snmpwalk
- Never repeat an action already listed as completed
- If all non-gateway devices are fully investigated, set ACTION: NONE
SYSEOF

    AI_CONTEXT="NETWORK INFORMATION:"$'\n'
    AI_CONTEXT+="  SSID    : ${SSID:-unknown}"$'\n'
    AI_CONTEXT+="  Subnet  : $SUBNET"$'\n'
    AI_CONTEXT+="  Gateway : ${GATEWAY:-unknown}  <-- OUT OF SCOPE, NEVER INVESTIGATE THIS IP"$'\n'
    AI_CONTEXT+="  Channel : ${WIFI_CHANNEL:-unknown}"$'\n\n'

    if [[ -f "$SHARED_DIR/reports/mdns_services.txt" ]]; then
        AI_CONTEXT+="$(cat "$SHARED_DIR/reports/mdns_services.txt")"$'\n\n'
    fi

    AI_CONTEXT+="DEVICE SCAN REPORTS (gateway excluded):"$'\n'
    for HOST in "${HOSTS[@]}"; do
        [[ "$HOST" == "$GATEWAY" ]] && continue
        RFILE="$SHARED_DIR/reports/device_${HOST//./_}.txt"
        [[ -f "$RFILE" ]] && AI_CONTEXT+="$(cat "$RFILE")"$'\n\n'
    done

    # ── Helper: call Ollama and return response text ──
    call_ollama() {
        local PAYLOAD_FILE="$1"
        local RAW
        RAW=$(curl -s --max-time 90 --retry 1 --retry-delay 3 \
            http://localhost:11434/api/generate \
            -H "Content-Type: application/json" \
            -d @"$PAYLOAD_FILE" 2>/dev/null)

        [[ -z "$RAW" ]] && { echo ""; return 1; }

        echo "$RAW" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('response', ''))
except:
    print('')
" 2>/dev/null
    }

    # ── Helper: normalise response — handles comma-separated fields ──
    normalize_response() {
        local RAW="$1"
        echo "$RAW" \
            | sed 's/,[ ]*SEVERITY:/\nSEVERITY:/g' \
            | sed 's/,[ ]*DEVICE:/\nDEVICE:/g'     \
            | sed 's/,[ ]*FINDING:/\nFINDING:/g'   \
            | sed 's/,[ ]*ACTION:/\nACTION:/g'     \
            | sed 's/,[ ]*REASON:/\nREASON:/g'
    }

    while [[ $LOOP_NUM -lt $MAX_LOOPS ]]; do
        LOOP_NUM=$(( LOOP_NUM + 1 ))
        echo "$LOOP_NUM" > "$SHARED_DIR/loop_count"

        TURN_PREFIX="$SHARED_DIR/ai_turns/turn_$(printf '%03d' $LOOP_NUM)"

        advance "Phase 3 -- AI analysis loop $LOOP_NUM of $MAX_LOOPS"
        echo "  [*] AI Loop $LOOP_NUM / $MAX_LOOPS"

        SEEN_STR=""
        for SA in "${SEEN_ACTIONS[@]}"; do
            SEEN_STR+="  - $SA"$'\n'
        done

        {
            echo "$AI_CONTEXT"
            echo ""
            echo "Actions already completed (DO NOT repeat any of these):"
            if [[ -z "$SEEN_STR" ]]; then
                echo "  (none yet)"
            else
                echo "$SEEN_STR"
            fi
            echo ""
            echo "Based on the scan data above, identify the single most important"
            echo "unaddressed vulnerability across all non-gateway devices."
            echo ""
            echo "CRITICAL REMINDER: Respond with EXACTLY 5 lines, nothing else."
            echo "Your first line must start with 'SEVERITY:' immediately."
            echo "Do not write any text before SEVERITY: or after REASON:"
        } > "${TURN_PREFIX}_prompt.txt"

        python3 - << PYEOF > "${TURN_PREFIX}_payload.json"
import json
system_prompt = open("$SHARED_DIR/ai_system.txt").read()
user_prompt   = open("${TURN_PREFIX}_prompt.txt").read()
payload = {
    "model": "$MODEL",
    "system": system_prompt,
    "prompt": user_prompt,
    "stream": False
}
print(json.dumps(payload))
PYEOF

        write_ai_feed ""
        write_ai_feed "--- LOOP $LOOP_NUM ---"
        write_ai_feed "Querying AI model..."

        OLLAMA_RESPONSE=$(call_ollama "${TURN_PREFIX}_payload.json")

        if [[ -z "$OLLAMA_RESPONSE" ]]; then
            echo "  [!] Ollama did not respond in time. Skipping loop $LOOP_NUM."
            write_ai_feed "TIMEOUT: Ollama did not respond for loop $LOOP_NUM."
            continue
        fi

        echo "$OLLAMA_RESPONSE" > "${TURN_PREFIX}_response.txt"

        NORMALIZED=$(normalize_response "$OLLAMA_RESPONSE")

        write_ai_feed ""
        write_ai_feed "$NORMALIZED"
        echo ""
        echo "  AI Response:"
        echo "$NORMALIZED" | sed 's/^/    /'
        echo ""

        # ── Parse fields ──
        SEVERITY=$(echo "$NORMALIZED"  | grep -m1 "^SEVERITY:" | sed 's/^SEVERITY:[[:space:]]*//' | tr -d '\r' | cut -d',' -f1 | xargs)
        DEVICE_AI=$(echo "$NORMALIZED" | grep -m1 "^DEVICE:"   | sed 's/^DEVICE:[[:space:]]*//'   | tr -d '\r' | cut -d',' -f1 | xargs)
        FINDING=$(echo "$NORMALIZED"   | grep -m1 "^FINDING:"  | sed 's/^FINDING:[[:space:]]*//'  | tr -d '\r')
        ACTION=$(echo "$NORMALIZED"    | grep -m1 "^ACTION:"   | sed 's/^ACTION:[[:space:]]*//'   | tr -d '\r' | cut -d',' -f1 | xargs)
        REASON=$(echo "$NORMALIZED"    | grep -m1 "^REASON:"   | sed 's/^REASON:[[:space:]]*//'   | tr -d '\r')

        echo "  [>] Severity : ${SEVERITY:-not parsed}"
        echo "  [>] Device   : ${DEVICE_AI:-not parsed}"
        echo "  [>] Finding  : ${FINDING:-not parsed}"
        echo "  [>] Action   : ${ACTION:-not parsed}"
        echo ""

        # ── Validate all required fields are present ──
        if [[ -z "$ACTION" || -z "$SEVERITY" || -z "$DEVICE_AI" ]]; then
            echo "  [!] AI produced invalid format. Injecting correction and retrying..."
            write_ai_feed "WARNING: AI format failure on loop $LOOP_NUM — retrying with correction."
            AI_CONTEXT+=$'\n'"[SYSTEM NOTE: Loop $LOOP_NUM failed to follow the required format. You MUST output exactly 5 lines: SEVERITY:, DEVICE:, FINDING:, ACTION:, REASON: — no other text whatsoever.]"
            continue
        fi

        # ── NONE check ──
        if [[ "$(echo "$ACTION" | tr '[:lower:]' '[:upper:]')" == "NONE" ]]; then
            echo "  [+] AI signals no further investigation needed."
            write_ai_feed ""
            write_ai_feed "COMPLETE: ACTION: NONE received after $LOOP_NUM loop(s)."
            LOOP_NUM=$(( LOOP_NUM - 1 ))
            break
        fi

        # ── Tool allowlist check ──
        FIRST_WORD=$(echo "$ACTION" | awk '{print $1}')
        VALID_TOOL=false
        for T in "${ALLOWED_TOOLS[@]}"; do
            [[ "$FIRST_WORD" == "$T" ]] && { VALID_TOOL=true; break; }
        done

        if ! $VALID_TOOL; then
            echo "  [!] '$FIRST_WORD' is not a permitted tool. Skipping this loop."
            write_ai_feed "SKIPPED: '$FIRST_WORD' not in allowed tool list."
            AI_CONTEXT+=$'\n'"[Loop $LOOP_NUM skipped: disallowed tool '$FIRST_WORD'. You MUST output a raw terminal command starting with nmap, nikto, sslscan, curl, or snmpwalk. Do NOT output English advice like 'Update' or 'Patch'.]"
            continue
        fi

        # ── Strip shell operators ──
        SAFE_ACTION=$(echo "$ACTION" | sed 's/[|;&].*$//' | xargs)

        if [[ "$SAFE_ACTION" =~ [\$\>\<\`\\] ]]; then
            echo "  [!] Illegal shell characters detected. Blocked."
            write_ai_feed "BLOCKED: Action contains illegal shell characters."
            AI_CONTEXT+=$'\n'"[Loop $LOOP_NUM blocked: illegal shell characters in action]"
            continue
        fi

        # ── Gateway scope check ──
        if [[ -n "$GATEWAY" ]] && echo "$SAFE_ACTION" | grep -q "$GATEWAY"; then
            echo "  [!] AI attempted to target gateway $GATEWAY. Blocked."
            write_ai_feed "BLOCKED: AI tried to target gateway $GATEWAY."
            AI_CONTEXT+=$'\n'"[Loop $LOOP_NUM blocked: attempted to target gateway $GATEWAY — it is OUT OF SCOPE]"
            continue
        fi

        # ── Duplicate action check ──
        IS_DUP=false
        for SA in "${SEEN_ACTIONS[@]}"; do
            [[ "$SA" == "$SAFE_ACTION" ]] && { IS_DUP=true; break; }
        done

        if $IS_DUP; then
            echo "  [!] Duplicate action detected. Skipping."
            write_ai_feed "SKIPPED: duplicate action — choose a different device or category."
            AI_CONTEXT+=$'\n'"[Loop $LOOP_NUM skipped: duplicate action — choose a different device or investigation category]"
            continue
        fi

        SEEN_ACTIONS+=("$SAFE_ACTION")

        echo "  [>] Executing: $SAFE_ACTION"
        write_ai_feed ""
        write_ai_feed "EXECUTING: $SAFE_ACTION"

        CMD_OUTPUT=$(bash -c "$SAFE_ACTION" 2>&1 | head -100)

        echo "$CMD_OUTPUT" | sed 's/^/    /'
        echo ""
        write_ai_feed "$CMD_OUTPUT"

        AI_CONTEXT+=$'\n\n'"=== Loop $LOOP_NUM result: $SAFE_ACTION ==="$'\n'"$CMD_OUTPUT"

        if [[ -n "$DEVICE_AI" ]]; then
            CLEAN_IP="${DEVICE_AI//./_}"
            RFILE="$SHARED_DIR/reports/device_${CLEAN_IP}.txt"
            if [[ -f "$RFILE" ]]; then
                {
                    echo ""
                    echo "--- AI Loop $LOOP_NUM: $SAFE_ACTION ---"
                    echo "$CMD_OUTPUT"
                } >> "$RFILE"
            fi
        fi

        echo ""
    done

    if [[ $LOOP_NUM -ge $MAX_LOOPS ]]; then
        write_ai_feed ""
        write_ai_feed "COMPLETE: Max loop count ($MAX_LOOPS) reached."
    fi

    # ─────────────────────────────────────────────────────────────
    #  PHASE 4 — FINAL REPORT
    # ─────────────────────────────────────────────────────────────
    generate_final_report() {
        local COLS DIV CREDIT CPAD IDX H RFILE
        COLS=$(tput cols 2>/dev/null || echo 80)
        DIV=$(printf '=%.0s' $(seq 1 "$COLS"))
        local SCAN_END
        SCAN_END=$(date)

        {
            echo "$DIV"
            echo "  WIFI SECURITY AUDIT -- FINAL REPORT"
            echo "$DIV"
            echo "  Network   : ${SSID:-unknown}"
            echo "  Subnet    : $SUBNET"
            echo "  Gateway   : ${GATEWAY:-unknown}  [excluded from scan]"
            echo "  BSSID     : ${WIFI_BSSID:-unknown}"
            echo "  Channel   : ${WIFI_CHANNEL:-unknown}"
            echo "  Started   : $SCAN_START"
            echo "  Completed : $SCAN_END"
            echo "  Hosts     : ${#HOSTS[@]}"
            echo "  AI Loops  : $LOOP_NUM"
            echo "$DIV"
            echo ""

            for H in "${HOSTS[@]}"; do
                echo "$DIV"
                printf "  DEVICE: %s" "$H"
                [[ "$H" == "$GATEWAY"  ]] && printf "  [Gateway -- excluded from deep scan]"
                [[ "$H" == "$LOCAL_IP" ]] && printf "  [This Machine]"
                echo ""
                echo "$DIV"

                if [[ "$H" == "$GATEWAY" ]]; then
                    echo "  Gateway was excluded from all deep scanning."
                    echo ""
                    continue
                fi

                RFILE="$SHARED_DIR/reports/device_${H//./_}.txt"
                if [[ -f "$RFILE" ]]; then
                    cat "$RFILE"
                else
                    echo "  No report data for this host."
                fi
                echo ""
            done

            echo "$DIV"
            echo "  AI INVESTIGATION SUMMARY"
            echo "$DIV"
            if [[ ${#SEEN_ACTIONS[@]} -eq 0 ]]; then
                echo "  No AI-directed actions were executed."
            else
                for (( IDX=0; IDX<${#SEEN_ACTIONS[@]}; IDX++ )); do
                    printf "  [%02d]  %s\n" "$(( IDX + 1 ))" "${SEEN_ACTIONS[$IDX]}"
                done
            fi

            echo ""
            echo "$DIV"
            echo "  END OF REPORT"
            echo "$DIV"
        } > "$SHARED_DIR/final_report.txt"

        advance "Phase 4 -- Generating AI Executive Summary..."
        echo "  [*] Generating AI Executive Summary from audit data..."
        write_ai_feed ""
        write_ai_feed "=== GENERATING FINAL AI REPORT ==="

        {
            cat << 'SYSEOF'
You are a senior cybersecurity consultant. Write a professional executive summary of the network security audit results below.

Structure your response exactly as follows:

EXECUTIVE OVERVIEW
[2-3 sentences summarising the audit scope, number of devices, and overall risk level]

CRITICAL FINDINGS
[Bullet list of the most serious vulnerabilities — include specific IP addresses and port numbers]

MEDIUM / LOW FINDINGS
[Brief bullet list of lower-severity items worth noting]

RECOMMENDATIONS
[Numbered list of prioritised remediation steps, most urgent first]

Rules: Be concise and professional. Reference specific IP addresses. Do not reproduce raw tool output. Focus on what an IT manager needs to act on immediately.

RAW AUDIT DATA BELOW:
SYSEOF
            cat "$SHARED_DIR/final_report.txt"
        } > "$SHARED_DIR/ai_summary_prompt.txt"

        python3 - << PYEOF > "$SHARED_DIR/ai_summary_payload.json"
import json
prompt = open("$SHARED_DIR/ai_summary_prompt.txt").read()
payload = {
    "model": "$MODEL",
    "prompt": prompt,
    "stream": False
}
print(json.dumps(payload))
PYEOF

        AI_SUMMARY_RAW=$(curl -s --max-time 180 --retry 1 \
            http://localhost:11434/api/generate \
            -H "Content-Type: application/json" \
            -d @"$SHARED_DIR/ai_summary_payload.json" 2>/dev/null)

        AI_SUMMARY=$(echo "$AI_SUMMARY_RAW" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('response', ''))
except:
    print('Failed to generate AI summary.')
" 2>/dev/null)

        echo "$AI_SUMMARY" > "$SHARED_DIR/ai_final_report.txt"

        advance "Phase 4 -- Final report generated"
        sleep 1

        echo ""
        echo "  [+] Audit complete. Final AI report is in the Monitor terminal."
        echo "  [+] Raw scan logs remain visible in this terminal."
        echo ""

        CREDIT="WiFi Security Audit Tool  --  Made by Hriday Patel"
        CPAD=$(( (COLS - ${#CREDIT}) / 2 ))
        [[ $CPAD -lt 0 ]] && CPAD=0
        printf "%${CPAD}s%s\n" "" "$CREDIT"
        echo ""
    }

    generate_final_report
    write_status "SCAN COMPLETE"
    touch "$SHARED_DIR/done"
    sleep 3
    exit 0
fi

# ═══════════════════════════════════════════════════════════════
#  LAUNCHER — Cleans stale runs, opens both terminals side by side
# ═══════════════════════════════════════════════════════════════

if pgrep -f "bash.*$(basename "$0").*--scanner" >/dev/null 2>&1; then
    echo "  [!] A WiFi scan is already running. Please close its terminals or wait for it to finish."
    exit 0
fi

LAUNCHER_GUARD="/tmp/wifiscan_launcher.pid"
if [[ -f "$LAUNCHER_GUARD" ]]; then
    OLD_PID=$(cat "$LAUNCHER_GUARD" 2>/dev/null)
    if kill -0 "$OLD_PID" 2>/dev/null; then
        exit 0
    fi
fi
echo $$ > "$LAUNCHER_GUARD"
trap 'rm -f "$LAUNCHER_GUARD"' EXIT INT TERM HUP

for OLD_DIR in /tmp/wifiscan_*; do
    [[ -d "$OLD_DIR" ]] && rm -rf "$OLD_DIR" 2>/dev/null
done

SHARED_DIR=$(mktemp -d /tmp/wifiscan_XXXXXX)
touch "$SHARED_DIR/log"
touch "$SHARED_DIR/current"
touch "$SHARED_DIR/ai_feed"
echo "0" > "$SHARED_DIR/stage"
echo "0" > "$SHARED_DIR/stage_total"
echo "0" > "$SHARED_DIR/loop_count"

echo "  Launching WiFi Security Audit Tool..."

osascript << EOF
tell application "Finder"
    set screenBounds to bounds of window of desktop
    set screenW to item 3 of screenBounds
    set screenH to item 4 of screenBounds
end tell

set halfW to screenW div 2
set menuBarH to 23

tell application "Terminal"
    activate

    do script "clear; bash '$SCRIPT_PATH' --scanner '$SHARED_DIR'"
    delay 0.8
    set w1 to front window
    set bounds of w1 to {0, menuBarH, halfW, screenH}
    set custom title of tab 1 of w1 to "[ SCANNER ]  WiFi Security Audit  --  Hriday Patel"
    set background color of (current settings of tab 1 of w1) to {2000, 2000, 2000}

    delay 0.5

    do script "clear; bash '$SCRIPT_PATH' --monitor '$SHARED_DIR'"
    delay 0.8
    set w2 to front window
    set bounds of w2 to {halfW, menuBarH, screenW, screenH}
    set custom title of tab 1 of w2 to "[ AI FEED ]  WiFi Security Audit  --  Hriday Patel"
    set background color of (current settings of tab 1 of w2) to {2000, 2000, 2000}

end tell
EOF

echo "  Both terminals launched."