#!/bin/bash

# ═══════════════════════════════════════════════════════════════
#  OSINT LOOKUP TOOL — Dual Terminal Edition  v3.4
#  Made by Hriday Patel
#  For educational/research use on data you have permission to query.
# ═══════════════════════════════════════════════════════════════

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MODE="${1:-launcher}"
SHARED_DIR="${2:-}"

# ───────────────────────────────────────────────────────────────
#  ASCII ART
# ───────────────────────────────────────────────────────────────
print_ascii_art() {
    local COLS
    COLS=$(tput cols 2>/dev/null || echo 100)
    local ART=(
        " ██╗  ██╗██████╗ ██╗██████╗  █████╗ ██╗   ██╗    ██████╗  █████╗ ████████╗███████╗██╗     "
        " ██║  ██║██╔══██╗██║██╔══██╗██╔══██╗╚██╗ ██╔╝    ██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██║     "
        " ███████║██████╔╝██║██║  ██║███████║ ╚████╔╝     ██████╔╝███████║   ██║   █████╗  ██║     "
        " ██╔══██║██╔══██╗██║██║  ██║██╔══██║  ╚██╔╝      ██╔═══╝ ██╔══██║   ██║   ██╔══╝  ██║     "
        " ██║  ██║██║  ██║██║██████╔╝██║  ██║   ██║       ██║     ██║  ██║   ██║   ███████╗███████╗"
        " ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═════╝ ╚═╝  ╚═╝   ╚═╝       ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝"
    )
    echo ""
    for LINE in "${ART[@]}"; do
        local PAD=$(( (COLS - ${#LINE}) / 2 ))
        [[ $PAD -lt 0 ]] && PAD=0
        printf "%${PAD}s%s\n" "" "$LINE"
    done
    echo ""
}

# ───────────────────────────────────────────────────────────────
#  HELPERS & TIMEOUT ENGINE
# ───────────────────────────────────────────────────────────────
cmd_exists() { command -v "$1" &>/dev/null; }

write_status() {
    echo "$1" > "$SHARED_DIR/current"
    echo "$1" >> "$SHARED_DIR/log"
}

write_stage() {
    echo "$1" > "$SHARED_DIR/stage"
    echo "$2" > "$SHARED_DIR/stage_total"
}

# Force-kill engine to prevent Python multiprocessing zombie hangs
run_with_timeout() {
    local max_time=$1
    shift
    # Run in subshell with monitor mode disabled to suppress "Killed: 9" shell prints
    (
        set +m
        "$@" &
        local pid=$!
        local count=0
        while kill -0 "$pid" 2>/dev/null; do
            sleep 1
            count=$((count + 1))
            if [[ $count -ge $max_time ]]; then
                kill -9 "$pid" 2>/dev/null
                exit 124
            fi
        done
        wait "$pid" 2>/dev/null
        exit $?
    ) 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════
#  TAB 2 — MONITOR
# ═══════════════════════════════════════════════════════════════
if [[ "$MODE" == "--monitor" ]]; then

    [[ -z "$SHARED_DIR" || ! -d "$SHARED_DIR" ]] && exit 0
    trap 'rm -rf "$SHARED_DIR"' EXIT INT TERM HUP

    SPINNER_FRAMES=('|' '/' '-' '\')
    SPIN_IDX=0

    draw_bar() {
        local CURRENT=$1
        local TOTAL=$2
        local WIDTH=40
        local FILLED=0
        [[ $TOTAL -gt 0 ]] && FILLED=$(( (CURRENT * WIDTH) / TOTAL ))
        local EMPTY=$(( WIDTH - FILLED ))
        local PCT=0
        [[ $TOTAL -gt 0 ]] && PCT=$(( (CURRENT * 100) / TOTAL ))
        local BAR=""
        for (( i=0; i<FILLED; i++ )); do BAR+="#"; done
        for (( i=0; i<EMPTY; i++ )); do BAR+="-"; done
        printf "  [%s] %d/%d (%d%%)\n" "$BAR" "$CURRENT" "$TOTAL" "$PCT"
    }

    draw_screen() {
        local COLS
        COLS=$(tput cols 2>/dev/null || echo 100)
        local DIV
        DIV=$(printf '=%.0s' $(seq 1 "$COLS"))

        clear
        print_ascii_art

        echo "$DIV"
        local TITLE="OSINT LOOKUP TOOL  --  LIVE STATUS MONITOR"
        local PAD=$(( (COLS - ${#TITLE}) / 2 ))
        [[ $PAD -lt 0 ]] && PAD=0
        printf "%${PAD}s%s\n" "" "$TITLE"
        echo "$DIV"
        echo ""

        local STAGE=0
        local TOTAL=0
        [[ -f "$SHARED_DIR/stage" ]]       && STAGE=$(cat "$SHARED_DIR/stage" 2>/dev/null)
        [[ -f "$SHARED_DIR/stage_total" ]] && TOTAL=$(cat "$SHARED_DIR/stage_total" 2>/dev/null)
        [[ -z "$STAGE" ]] && STAGE=0
        [[ -z "$TOTAL" ]] && TOTAL=0

        echo "  PROGRESS"
        draw_bar "$STAGE" "$TOTAL"
        echo ""

        local SPINNER="${SPINNER_FRAMES[$SPIN_IDX]}"
        SPIN_IDX=$(( (SPIN_IDX + 1) % 4 ))

        local CURRENT=""
        [[ -f "$SHARED_DIR/current" ]] && CURRENT=$(cat "$SHARED_DIR/current" 2>/dev/null)
        [[ -z "$CURRENT" ]] && CURRENT="Waiting for scan to begin..."

        echo "  STATUS"
        printf "  [%s]  %s\n" "$SPINNER" "$CURRENT"
        echo ""

        if [[ -f "$SHARED_DIR/log" ]]; then
            echo "$DIV"
            echo "  ACTIVITY LOG"
            echo "$DIV"
            tail -20 "$SHARED_DIR/log" 2>/dev/null | while IFS= read -r line; do
                printf "  %s\n" "$line"
            done
        fi

        echo ""
        echo "$DIV"
    }

    while [[ ! -f "$SHARED_DIR/done" ]]; do
        [[ ! -d "$SHARED_DIR" ]] && exit 0
        draw_screen
        sleep 0.3
    done

    show_final_screen() {
        local COLS
        COLS=$(tput cols 2>/dev/null || echo 100)
        local DIV
        DIV=$(printf '=%.0s' $(seq 1 "$COLS"))

        clear
        print_ascii_art

        echo "$DIV"
        local MSG="ALL SCANS COMPLETE"
        local PAD=$(( (COLS - ${#MSG}) / 2 ))
        [[ $PAD -lt 0 ]] && PAD=0
        printf "%${PAD}s%s\n" "" "$MSG"
        echo "$DIV"
        echo ""

        if [[ -f "$SHARED_DIR/log" ]]; then
            echo "  FULL ACTIVITY LOG"
            echo "$DIV"
            cat "$SHARED_DIR/log"
        fi

        echo ""
        echo "$DIV"
        echo ""

        local CREDIT="OSINT Script made by Hriday Patel  |  v3.4"
        local CPAD=$(( (COLS - ${#CREDIT}) / 2 ))
        [[ $CPAD -lt 0 ]] && CPAD=0
        printf "%${CPAD}s%s\n" "" "$CREDIT"

        echo ""
        echo "$DIV"
        echo ""
        print_ascii_art
        echo "$DIV"
    }

    show_final_screen
    exit 0
fi

# ═══════════════════════════════════════════════════════════════
#  TAB 1 — SCANNER
# ═══════════════════════════════════════════════════════════════
if [[ "$MODE" == "--scanner" ]]; then

    [[ -z "$SHARED_DIR" || ! -d "$SHARED_DIR" ]] && exit 0
    trap 'rm -rf "$SHARED_DIR"' EXIT INT TERM HUP

    export PATH="$PATH:$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:$HOME/go/bin"

    clear
    echo ""
    echo "=============================================="
    echo "        OSINT LOOKUP TOOL -- SCANNER v3.4"
    echo "        Made by Hriday Patel"
    echo "=============================================="
    echo ""
    echo "  [*] Checking dependencies..."
    echo ""

    # ── Bootstrap: Homebrew ─────────────────────────────────────
    if ! cmd_exists brew; then
        echo "  [!] Homebrew not found. Installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        cmd_exists brew || { echo "  [X] Homebrew failed. Visit https://brew.sh"; exit 1; }
        echo "  [+] Homebrew installed."
    else
        echo "  [+] brew              OK"
    fi

    # ── Bootstrap: pipx ─────────────────────────────────────────
    if ! cmd_exists pipx; then
        echo "  [!] pipx not found. Installing..."
        brew install pipx && pipx ensurepath
        export PATH="$PATH:$HOME/.local/bin"
        cmd_exists pipx || { echo "  [X] pipx install failed."; exit 1; }
        echo "  [+] pipx              OK"
    else
        echo "  [+] pipx              OK"
    fi

    export PATH="$PATH:$HOME/.local/bin"
    eval "$(pipx ensurepath --force 2>/dev/null | grep 'export PATH' || true)"

    # ── Bootstrap: Go ────────────────────────────────────────────
    if ! cmd_exists go; then
        brew install go &>/dev/null
        echo "  [+] go installed."
    else
        echo "  [+] go                OK"
    fi

    # ─────────────────────────────────────────────────────────────
    safe_install() {
        local CMD="$1"
        local PKG="$2"
        local METHOD="${3:-pipx}"

        if cmd_exists "$CMD"; then
            printf "  [+] %-28s OK\n" "$CMD"
            return 0
        fi

        echo "  [!] $CMD not found. Installing..."

        case "$METHOD" in
            pipx)
                pipx install "$PKG" &>/dev/null
                export PATH="$PATH:$HOME/.local/bin"
                cmd_exists "$CMD" && { echo "  [+] $CMD installed."; return 0; }
                pip3 install "$PKG" --break-system-packages &>/dev/null
                export PATH="$PATH:$HOME/.local/bin"
                cmd_exists "$CMD" && { echo "  [+] $CMD installed."; return 0; }
                pip3 install "$PKG" --user &>/dev/null
                export PATH="$PATH:$HOME/.local/bin"
                ;;
            brew)
                brew install "$PKG" &>/dev/null
                ;;
            go)
                go install "$PKG" &>/dev/null
                export PATH="$PATH:$HOME/go/bin"
                ;;
        esac

        export PATH="$PATH:$HOME/.local/bin:$HOME/go/bin"
        if cmd_exists "$CMD"; then
            echo "  [+] $CMD installed."
        else
            echo "  [~] $CMD install failed — will skip during scan."
        fi
    }

    # ─────────────────────────────────────────────────────────────
    clone_install() {
        local CMD="$1"
        local REPO_URL="$2"
        local SCRIPT_HINT="${3:-}"
        local INSTALL_DIR="$HOME/.local/share/$CMD"

        if cmd_exists "$CMD"; then
            printf "  [+] %-28s OK\n" "$CMD"
            return 0
        fi

        echo "  [!] $CMD not found. Installing..."
        rm -rf "$INSTALL_DIR"

        if ! git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" &>/dev/null; then
            echo "  [~] $CMD clone failed — will skip during scan."
            return 1
        fi

        if [[ -f "$INSTALL_DIR/requirements.txt" ]]; then
            pip3 install -r "$INSTALL_DIR/requirements.txt" \
                --break-system-packages &>/dev/null || \
            pip3 install -r "$INSTALL_DIR/requirements.txt" \
                --user &>/dev/null
        fi

        local FOUND_SCRIPT=""

        if [[ -n "$SCRIPT_HINT" ]]; then
            FOUND_SCRIPT=$(find "$INSTALL_DIR" -maxdepth 5 \
                -name "$SCRIPT_HINT" ! -path "*/__pycache__/*" | head -1)
        fi

        if [[ -z "$FOUND_SCRIPT" ]]; then
            for CANDIDATE in "${CMD}.py" "main.py" "run.py" "cli.py" "app.py" "__main__.py"; do
                FOUND_SCRIPT=$(find "$INSTALL_DIR" -maxdepth 5 \
                    -name "$CANDIDATE" ! -path "*/__pycache__/*" | head -1)
                [[ -n "$FOUND_SCRIPT" ]] && break
            done
        fi

        if [[ -z "$FOUND_SCRIPT" ]]; then
            FOUND_SCRIPT=$(find "$INSTALL_DIR" -maxdepth 1 \
                -name "*.py" \
                ! -name "setup.py" ! -name "setup_*.py" \
                ! -name "test*.py" ! -name "test_*.py" \
                ! -path "*/__pycache__/*" | head -1)
        fi

        if [[ -z "$FOUND_SCRIPT" ]]; then
            echo "  [~] $CMD cloned but no entry-point found — will skip."
            return 1
        fi

        mkdir -p "$HOME/.local/bin"
        printf '#!/bin/bash\npython3 "%s" "$@"\n' "$FOUND_SCRIPT" \
            > "$HOME/.local/bin/$CMD"
        chmod +x "$HOME/.local/bin/$CMD"
        export PATH="$PATH:$HOME/.local/bin"

        if cmd_exists "$CMD"; then
            echo "  [+] $CMD installed."
        else
            echo "  [~] $CMD wrapper created but not found in PATH — will skip."
        fi
    }

    # ── Standard Pip / Brew / Go Tools ───────────────────────────
    safe_install holehe       holehe
    safe_install h8mail       h8mail
    safe_install emailfinder  emailfinder
    safe_install ignorant     ignorant
    safe_install socialscan   socialscan
    safe_install theHarvester theHarvester
    safe_install phoneinfoga  phoneinfoga brew
    
    safe_install dnstwist     dnstwist
    # Fix for dnstwist missing DNS features
    if ! python3 -c "import dns" &>/dev/null; then
        pip3 install dnspython --break-system-packages &>/dev/null || \
        pip3 install dnspython --user &>/dev/null
    fi

    safe_install sherlock     sherlock-project
    safe_install maigret      maigret
    safe_install sublist3r    sublist3r
    safe_install crosslinked  crosslinked
    
    # safe_install metagoofil   metagoofil
    # safe_install maryam       owasp-maryam

    # ── osrframework (mailfy / phonefy) ──────────────────────────
    if ! cmd_exists mailfy || ! cmd_exists phonefy; then
        pipx install osrframework &>/dev/null || \
        pip3 install osrframework --break-system-packages &>/dev/null
        export PATH="$PATH:$HOME/.local/bin"
    fi
    cmd_exists mailfy   && printf "  [+] %-28s OK\n" "mailfy"   || echo "  [~] mailfy unavailable — will skip."
    cmd_exists phonefy  && printf "  [+] %-28s OK\n" "phonefy"  || echo "  [~] phonefy unavailable — will skip."

    # ── Go-based Tools ───────────────────────────────────────────
    if ! cmd_exists mosint; then
        echo "  [!] mosint not found. Installing..."
        go install github.com/alpkeskin/mosint/v3/cmd/mosint@latest &>/dev/null
        export PATH="$PATH:$HOME/go/bin"
    fi
    cmd_exists mosint && printf "  [+] %-28s OK\n" "mosint" || echo "  [~] mosint unavailable."

    if ! cmd_exists amass; then
        brew install amass &>/dev/null || \
        go install github.com/owasp-amass/amass/v4/...@master &>/dev/null
        export PATH="$PATH:$HOME/go/bin"
    fi
    cmd_exists amass && printf "  [+] %-28s OK\n" "amass" || echo "  [~] amass unavailable."

    if ! cmd_exists waybackurls; then
        go install github.com/tomnomnom/waybackurls@latest &>/dev/null
        export PATH="$PATH:$HOME/go/bin"
    fi
    cmd_exists waybackurls && printf "  [+] %-28s OK\n" "waybackurls" || echo "  [~] waybackurls unavailable."

    if ! cmd_exists gau; then
        go install github.com/lc/gau/v2/cmd/gau@latest &>/dev/null
        export PATH="$PATH:$HOME/go/bin"
    fi
    cmd_exists gau && printf "  [+] %-28s OK\n" "gau" || echo "  [~] gau unavailable."

    # Auto-generate minimal mosint config
    if [[ ! -f "$HOME/.mosint.yaml" ]]; then
        cat > "$HOME/.mosint.yaml" <<'MOSINTCFG'
services:
  hunter_io: ""
  emailrep_io: ""
  breachdirectory: ""
  intelx: ""
MOSINTCFG
        echo "  [+] Created minimal ~/.mosint.yaml"
    fi

    # ── GHunt ────────────────────────────────────────────────────
    if ! cmd_exists ghunt; then
        pipx install ghunt &>/dev/null || \
        pip3 install ghunt --break-system-packages &>/dev/null
        export PATH="$PATH:$HOME/.local/bin"
    fi
    cmd_exists ghunt && printf "  [+] %-28s OK\n" "ghunt" || echo "  [~] ghunt unavailable."

    # ── Spiderfoot ───────────────────────────────────────────────
    if ! cmd_exists sf; then
        pipx install spiderfoot &>/dev/null || \
        pip3 install spiderfoot --break-system-packages &>/dev/null
        SF_BIN=$(find "$HOME/Library/Python" "$HOME/.local" /usr/local/bin /opt/homebrew/bin -name "sf" -o -name "spiderfoot" 2>/dev/null | grep -v pycache | head -1)
        [[ -n "$SF_BIN" ]] && ln -sf "$SF_BIN" "$HOME/.local/bin/sf"
    fi
    cmd_exists sf && printf "  [+] %-28s OK\n" "sf (spiderfoot)" || echo "  [~] sf unavailable."

    # ── Shodan & Censys ──────────────────────────────────────────
    if ! cmd_exists shodan; then
        pipx install shodan &>/dev/null || pip3 install shodan --break-system-packages &>/dev/null
    fi
    cmd_exists shodan && printf "  [+] %-28s OK\n" "shodan" || echo "  [~] shodan unavailable."

    if ! cmd_exists censys; then
        pipx install censys &>/dev/null || pip3 install censys --break-system-packages &>/dev/null
    fi
    cmd_exists censys && printf "  [+] %-28s OK\n" "censys" || echo "  [~] censys unavailable."

    # ── Recon-ng ─────────────────────────────────────────────────
    if ! cmd_exists recon-ng; then
        pipx install recon-ng &>/dev/null || pip3 install recon-ng --break-system-packages &>/dev/null
    fi
    cmd_exists recon-ng && printf "  [+] %-28s OK\n" "recon-ng" || echo "  [~] recon-ng unavailable."

    # ── Git Cloned Repositories ──────────────────────────────────
    # NOTE: Dead repositories have been commented out to speed up checks and avoid errors.
    
    clone_install buster         "https://github.com/sham00n/buster.git"         "buster.py"
    clone_install whatbreach     "https://github.com/Ekultek/WhatBreach.git"     "whatbreach.py"
    clone_install photon         "https://github.com/s0md3v/Photon.git"          "photon.py"
    clone_install leaksearch     "https://github.com/JoelGMSec/LeakSearch.git"  "LeakSearch.py"
    clone_install EmailHarvester "https://github.com/maldevel/EmailHarvester.git" "EmailHarvester.py"
    clone_install SimplyEmail    "https://github.com/SimplySecurity/SimplyEmail.git" "SimplyEmail.py"
    clone_install phonerator     "https://github.com/Moham3dRiahi/Th3inspector.git" "Th3inspector.py"
    clone_install telespot       "https://github.com/thumpersecure/Telespot.git" "telespot.py"
    clone_install zehef          "https://github.com/N0rz3/Zehef.git"           "zehef.py"
    clone_install user-scanner   "https://github.com/kaifcodec/user-scanner.git" "user-scanner.py"
    clone_install phoneintel     "https://github.com/phoneintel/phoneintel.git" "phoneintel.py"
    clone_install tg-check       "https://github.com/bellingcat/telegram-phone-number-checker.git" "check_phone_number.py"

    # Dead repos removed from checks:
    # clone_install infoga "https://github.com/m4ll0k/Infoga.git" "infoga.py"
    # clone_install protosint "https://github.com/Proteque/Protosint.git" "protosint.py"
    # clone_install pwnedcheck "https://github.com/davidtavarez/pwnedcheck.git" "pwnedcheck.py"
    # clone_install osintsearch "https://github.com/Am0rphous/OSINT-Search.git" "osint.py"
    # clone_install epieo "https://github.com/Cyber-Dojo/epieo.git" "epieo.py"
    # clone_install detectdee "https://github.com/mxrch/DetectDee.git" "detectdee.py"

    echo ""
    echo "  [+] All dependencies checked."
    echo ""
    echo "=============================================="
    echo ""
    echo "  Enter details below. Leave blank to skip."
    echo ""
    read -rp "  Phone Number (e.g. +919876543210) : " PHONE
    read -rp "  Email Address                     : " EMAIL

    PHONE=$(echo "$PHONE" | xargs 2>/dev/null)
    EMAIL=$(echo "$EMAIL" | xargs 2>/dev/null)

    # Input Sanitization: Strip accidental spaces or equals signs from phone input
    if [[ -n "$PHONE" ]]; then
        PHONE=$(echo "$PHONE" | tr -cd '+0-9')
    fi

    if [[ -z "$PHONE" && -z "$EMAIL" ]]; then
        echo ""
        echo "  [X] No input provided. Exiting."
        exit 1
    fi

    echo "$EMAIL" > "$SHARED_DIR/email"
    echo "$PHONE" > "$SHARED_DIR/phone"

    # Pre-parse Email and Phone attributes
    DOMAIN=""
    USERNAME=""
    if [[ -n "$EMAIL" ]]; then
        DOMAIN=$(echo "$EMAIL" | cut -d'@' -f2)
        USERNAME=$(echo "$EMAIL" | cut -d'@' -f1)
    fi

    PHONE_RAW=""
    PHONE_CC=""
    PHONE_LOCAL=""
    if [[ -n "$PHONE" ]]; then
        PHONE_RAW=$(echo "$PHONE" | tr -cd '0-9')
        PHONE_CC=$(echo "$PHONE" | grep -oE '^\+[0-9]{1,3}' | tr -d '+')
        PHONE_LOCAL=$(echo "$PHONE" | sed "s/^\+${PHONE_CC}//")
        [[ -z "$PHONE_LOCAL" ]] && PHONE_LOCAL="$PHONE_RAW"
    fi

    # Calculate Total Execution Stages (2 stages per tool: start & complete)
    EMAIL_TOOL_COUNT=19  # Adjusted for dead tools removed
    PHONE_TOOL_COUNT=10

    TOTAL_STAGES=0
    [[ -n "$EMAIL" ]] && TOTAL_STAGES=$(( TOTAL_STAGES + (EMAIL_TOOL_COUNT * 2) ))
    [[ -n "$PHONE" ]] && TOTAL_STAGES=$(( TOTAL_STAGES + (PHONE_TOOL_COUNT * 2) ))
    CURRENT_STAGE=0
    write_stage "$CURRENT_STAGE" "$TOTAL_STAGES"

    clear
    echo ""
    echo "=============================================="
    echo "        OSINT LOOKUP TOOL -- SCANNER v3.4"
    echo "=============================================="
    echo "  Phone  : ${PHONE:-<not provided>}"
    echo "  Email  : ${EMAIL:-<not provided>}"
    echo "  Time   : $(date)"
    echo "=============================================="

    advance() {
        CURRENT_STAGE=$(( CURRENT_STAGE + 1 ))
        write_stage "$CURRENT_STAGE" "$TOTAL_STAGES"
        write_status "$1"
    }

    section() {
        echo ""
        echo "----------------------------------------------"
        echo "  >> $1"
        echo "----------------------------------------------"
    }

    # ═══════════════════════════════════════════════════════════
    #  EMAIL OSINT PIPELINE
    # ═══════════════════════════════════════════════════════════
    if [[ -n "$EMAIL" ]]; then
        echo ""
        echo "╔══════════════════════════════════════════╗"
        echo "║           EMAIL OSINT TOOLS               ║"
        echo "╚══════════════════════════════════════════╝"

        # 1. holehe
        section "holehe — Site registration check (120+ sites)"
        advance "[holehe] Scanning site registrations for $EMAIL"
        cmd_exists holehe && holehe "$EMAIL" || echo "  [!] holehe unavailable"
        advance "[holehe] Complete"

        # 2. socialscan
        section "socialscan — Account existence checker"
        advance "[socialscan] Checking $EMAIL across platforms"
        cmd_exists socialscan && socialscan "$EMAIL" || echo "  [!] socialscan unavailable"
        advance "[socialscan] Complete"

        # 3. mailfy
        section "mailfy — Email existence across 30+ platforms"
        advance "[mailfy] Checking $EMAIL across platforms"
        cmd_exists mailfy && mailfy -i "$EMAIL" 2>/dev/null || echo "  [!] mailfy unavailable"
        advance "[mailfy] Complete"

        # 4. buster
        section "buster — Breach data & social account links"
        advance "[buster] Deep scanning $EMAIL"
        cmd_exists buster && buster -e "$EMAIL" 2>/dev/null || echo "  [!] buster unavailable"
        advance "[buster] Complete"

        # 5. h8mail
        section "h8mail — Breach & cleartext leak check"
        advance "[h8mail] Checking breach databases for $EMAIL"
        cmd_exists h8mail && run_with_timeout 60 h8mail -t "$EMAIL" || echo "  [!] h8mail unavailable"
        advance "[h8mail] Complete"

        # 6. emailfinder
        section "emailfinder — Email domain recon"
        advance "[emailfinder] Scanning domain $DOMAIN"
        if cmd_exists emailfinder; then
            run_with_timeout 60 emailfinder -d "$DOMAIN" 2>/dev/null || echo "  [!] emailfinder encountered an error or timed out"
        else
            echo "  [!] emailfinder unavailable"
        fi
        advance "[emailfinder] Complete"

        # 7. mosint
        section "mosint — Multi-service email framework"
        advance "[mosint] Deep scanning $EMAIL"
        cmd_exists mosint && run_with_timeout 180 mosint "$EMAIL" || echo "  [!] mosint unavailable"
        advance "[mosint] Complete"

        # 8. whatbreach
        section "whatbreach — Multi-source breach aggregator"
        advance "[whatbreach] Checking breach sources for $EMAIL"
        if cmd_exists whatbreach; then
            printf '\n\n\n\n' | run_with_timeout 60 whatbreach -e "$EMAIL" 2>/dev/null || echo "  [!] whatbreach completed"
        else
            echo "  [!] whatbreach unavailable"
        fi
        advance "[whatbreach] Complete"

        # 9. spiderfoot
        section "spiderfoot — Automated email OSINT"
        advance "[spiderfoot] Running automated OSINT for $EMAIL"
        if cmd_exists sf; then
            run_with_timeout 180 sf -s "$EMAIL" -t EMAILADDR -q -o /tmp/sf_results_"$$".csv 2>/dev/null || true
            [[ -f /tmp/sf_results_"$$".csv ]] && cat /tmp/sf_results_"$$".csv
        else
            echo "  [!] spiderfoot unavailable"
        fi
        advance "[spiderfoot] Complete"

        # 10. dnstwist
        section "dnstwist — Domain variation & typosquatting"
        advance "[dnstwist] Scanning domain variations for $DOMAIN"
        cmd_exists dnstwist && run_with_timeout 180 dnstwist --registered "$DOMAIN" || echo "  [!] dnstwist unavailable"
        advance "[dnstwist] Complete"

        # 11. theHarvester
        section "theHarvester — Passive domain recon"
        advance "[theHarvester] Scanning domain: $DOMAIN"
        cmd_exists theHarvester && run_with_timeout 180 theHarvester -d "$DOMAIN" -b duckduckgo,certspotter,crtsh,hackertarget -l 100 || echo "  [!] theHarvester unavailable"
        advance "[theHarvester] Complete"

        # 12. sherlock
        section "sherlock — Username search across 400+ sites"
        advance "[sherlock] Searching username '$USERNAME' across platforms"
        cmd_exists sherlock && run_with_timeout 90 sherlock "$USERNAME" --timeout 10 || echo "  [!] sherlock unavailable"
        advance "[sherlock] Complete"

        # 13. maigret
        section "maigret — Deep username OSINT (1000+ sites)"
        advance "[maigret] Deep scanning username '$USERNAME'"
        cmd_exists maigret && run_with_timeout 120 maigret "$USERNAME" --no-progressbar 2>/dev/null || echo "  [!] maigret unavailable"
        advance "[maigret] Complete"

        # 14. GHunt
        section "GHunt — Google account intelligence"
        advance "[ghunt] Querying Google services for $EMAIL"
        cmd_exists ghunt && run_with_timeout 45 ghunt email "$EMAIL" 2>/dev/null || echo "  [!] GHunt unavailable or login needed"
        advance "[ghunt] Complete"

        # 15. Zehef
        section "Zehef — Account existence & disclosure search"
        advance "[zehef] Checking $EMAIL for public registrations"
        cmd_exists zehef && run_with_timeout 45 zehef -e "$EMAIL" 2>/dev/null || echo "  [!] zehef unavailable"
        advance "[zehef] Complete"

        # 16. user-scanner
        section "user-scanner — Reset endpoint & service scanner"
        advance "[user-scanner] Scanning $EMAIL against password reset vectors"
        cmd_exists user-scanner && run_with_timeout 120 user-scanner -e "$EMAIL" 2>/dev/null || echo "  [!] user-scanner unavailable"
        advance "[user-scanner] Complete"

        # 17. sublist3r
        section "sublist3r — Subdomain enumeration"
        advance "[sublist3r] Enumerating subdomains for $DOMAIN"
        if cmd_exists sublist3r; then
            run_with_timeout 90 sublist3r -d "$DOMAIN" -t 10 2>/dev/null || echo "  [!] sublist3r completed with errors or force-quit"
        else
            echo "  [!] sublist3r unavailable"
        fi
        advance "[sublist3r] Complete"

        # 18. amass
        section "amass — OWASP passive network intel"
        advance "[amass] Passive recon on $DOMAIN"
        cmd_exists amass && run_with_timeout 120 amass enum -passive -d "$DOMAIN" -timeout 2 2>/dev/null || echo "  [!] amass unavailable"
        advance "[amass] Complete"

        # 19. EmailHarvester
        section "EmailHarvester — Scrape public emails"
        advance "[EmailHarvester] Scraping emails from $DOMAIN"
        cmd_exists EmailHarvester && run_with_timeout 60 EmailHarvester -d "$DOMAIN" -e all 2>/dev/null || echo "  [!] EmailHarvester unavailable"
        advance "[EmailHarvester] Complete"

        # 20. waybackurls
        section "waybackurls — Archived URL discovery"
        advance "[waybackurls] Fetching archived URLs for $DOMAIN"
        cmd_exists waybackurls && echo "$DOMAIN" | run_with_timeout 45 waybackurls 2>/dev/null | head -50 || echo "  [!] waybackurls unavailable"
        advance "[waybackurls] Complete"

        # 21. leaksearch
        section "leaksearch — Paste site & leak search"
        advance "[leaksearch] Searching paste dumps for $EMAIL"
        if cmd_exists leaksearch; then
            run_with_timeout 45 leaksearch "$EMAIL" 2>/dev/null || echo "  [!] leaksearch returned no hits"
        else
            PASTE_HITS=$(curl -s --max-time 5 "https://psbdmp.cc/api/v3/search/$EMAIL" 2>/dev/null)
            [[ -n "$PASTE_HITS" && "$PASTE_HITS" != *"error"* ]] && echo "$PASTE_HITS" || echo "  [~] No paste dumps found"
        fi
        advance "[leaksearch] Complete"

        # 22. EmailRep API
        section "EmailRep.io — Email Reputation & Security Rating"
        advance "[emailrep] Querying reputation API for $EMAIL"
        REP_RES=$(curl -s --max-time 5 -H "User-Agent: OSINT-Tool" "https://emailrep.io/$EMAIL" 2>/dev/null)
        if [[ -n "$REP_RES" && "$REP_RES" == *"email"* ]]; then
            echo "$REP_RES" | python3 -m json.tool 2>/dev/null || echo "$REP_RES"
        else
            echo "  [~] EmailRep API rate limited or offline"
        fi
        advance "[emailrep] Complete"
    fi

    # ═══════════════════════════════════════════════════════════
    #  PHONE OSINT PIPELINE
    # ═══════════════════════════════════════════════════════════
    if [[ -n "$PHONE" ]]; then
        echo ""
        echo "╔══════════════════════════════════════════╗"
        echo "║           PHONE OSINT TOOLS               ║"
        echo "╚══════════════════════════════════════════╝"

        # 1. phoneinfoga
        section "phoneinfoga — Carrier, region & OSINT footprint"
        advance "[phoneinfoga] Scanning $PHONE"
        cmd_exists phoneinfoga && run_with_timeout 60 phoneinfoga scan -n "$PHONE" || echo "  [!] phoneinfoga unavailable"
        advance "[phoneinfoga] Complete"

        # 2. TeleSpot
        section "TeleSpot — Cross-engine phone pattern search"
        advance "[telespot] Searching search engines & DeHashed for $PHONE"
        cmd_exists telespot && run_with_timeout 90 telespot -p "+${PHONE_RAW}" 2>/dev/null || echo "  [!] telespot unavailable"
        advance "[telespot] Complete"

        # 3. ignorant
        section "ignorant — Social registration check via phone"
        advance "[ignorant] Checking Snapchat, Instagram, Amazon for $PHONE"
        if cmd_exists ignorant; then
            run_with_timeout 60 ignorant "$PHONE_CC" "$PHONE_LOCAL" 2>/dev/null || run_with_timeout 60 ignorant "+${PHONE_RAW}" 2>/dev/null
        else
            echo "  [!] ignorant unavailable"
        fi
        advance "[ignorant] Complete"

        # 4. phonefy
        section "phonefy — Phone number platform lookup"
        advance "[phonefy] Checking $PHONE across platforms"
        cmd_exists phonefy && run_with_timeout 60 phonefy -n "$PHONE" 2>/dev/null || echo "  [!] phonefy unavailable or failed"
        advance "[phonefy] Complete"

        # 5. PhoneIntel
        section "PhoneIntel — Carrier routing & line identification"
        advance "[phoneintel] Extracting carrier data for $PHONE"
        cmd_exists phoneintel && run_with_timeout 45 phoneintel -n "+${PHONE_RAW}" 2>/dev/null || echo "  [!] phoneintel unavailable"
        advance "[phoneintel] Complete"

        # 6. Telegram Checker
        section "telegram-phone-number-checker — Active Telegram account scan"
        advance "[tg-check] Verifying Telegram registration for $PHONE"
        cmd_exists tg-check && run_with_timeout 45 tg-check "+${PHONE_RAW}" < /dev/null 2>/dev/null || echo "  [!] tg-check skipped (Requires Telegram API Keys)"
        advance "[tg-check] Complete"

        # 7. sherlock (Numeric Pattern)
        section "sherlock — Scanning handles derived from $PHONE_LOCAL"
        advance "[sherlock] Searching numeric handle '$PHONE_LOCAL'"
        cmd_exists sherlock && run_with_timeout 90 sherlock "$PHONE_LOCAL" --timeout 10 2>/dev/null || echo "  [!] sherlock unavailable"
        advance "[sherlock] Complete"

        # 8. maigret (Numeric Pattern)
        section "maigret — Deep search on handle '$PHONE_LOCAL'"
        advance "[maigret] Deep scanning handle '$PHONE_LOCAL'"
        cmd_exists maigret && run_with_timeout 120 maigret "$PHONE_LOCAL" --no-progressbar 2>/dev/null || echo "  [!] maigret unavailable"
        advance "[maigret] Complete"

        # 9. spiderfoot
        section "spiderfoot — Automated phone OSINT scan"
        advance "[spiderfoot] Running automated OSINT for $PHONE"
        if cmd_exists sf; then
            run_with_timeout 180 sf -s "$PHONE" -t PHONE_NUM -q -o /tmp/sf_phone_"$$".csv 2>/dev/null || true
            [[ -f /tmp/sf_phone_"$$".csv ]] && cat /tmp/sf_phone_"$$".csv
        else
            echo "  [!] spiderfoot unavailable"
        fi
        advance "[spiderfoot] Complete"
    fi

    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║            SCAN COMPLETE                 ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""

    write_status "ALL SCANS FINISHED"
    touch "$SHARED_DIR/done"
    exit 0
fi

# ═══════════════════════════════════════════════════════════════
#  LAUNCHER MODE
# ═══════════════════════════════════════════════════════════════
SHARED_DIR=$(mktemp -d /tmp/osint_XXXXXX)
touch "$SHARED_DIR/log"
touch "$SHARED_DIR/current"
echo "0" > "$SHARED_DIR/stage"
echo "0" > "$SHARED_DIR/stage_total"

echo "  Launching OSINT Tool v3.4..."

osascript <<EOF
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
    set custom title of tab 1 of w1 to "[ TAB 1 ]  OSINT Scanner"
    set background color of (current settings of tab 1 of w1) to {2000, 2000, 2000}

    delay 0.5

    do script "clear; bash '$SCRIPT_PATH' --monitor '$SHARED_DIR'"
    delay 0.8
    set w2 to front window
    set bounds of w2 to {halfW, menuBarH, screenW, screenH}
    set custom title of tab 1 of w2 to "[ TAB 2 ]  OSINT Monitor"
    set background color of (current settings of tab 1 of w2) to {2000, 2000, 2000}

end tell
EOF

echo "  Both windows launched."
