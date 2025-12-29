#!/bin/bash

# --- 1. STRICT MODE & SAFETY ---
set -Eeuo pipefail
IFS=$'\n\t'

# --- 2. CONFIGURATION & VARIABLES ---
BOX=$(hostname)
BACKTITLE="© 2025 - David Šmidke - Homelab Docker Manager"
TITLE="\Z1\ZbDocker Host: $BOX"
SCRIPT_VERSION="1.8.5"
LAST_CONTAINER_FILE="/tmp/docker-manager.last"
LOG_LINES_FILE="/tmp/docker-manager.loglines"
PROTECTED_CONTAINERS=("portainer" "traefik" "watchtower" "diun" "docker-proxy")
TMP_FILES=()
DRY_RUN=0

# Filter patterns for noise reduction (DBs, logs, heavy data stores)
# NOTE: -name arguments cannot contain slashes!
NOISE_PRUNE_DIRS=(
    "postgres_data" "mariadb" "mysql" "mongodb" "redis" "influxdb" "prometheus_data" 
    "grafana_data" "journal" "diagnostic.data" "wal" "logs" "cache" "tmp" "temp" 
    "containerd" "db_storage" ".git" ".vscode" "portainer_data" "node_modules"
)

# View Mode State: "all" or "associated"
VIEW_MODE="associated"
FILTER_MODE="on" # "on" (Prune noise) or "off" (Show everything)

# Handle Dry Run flag
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# --- 3. CLEANUP TRAP ---
cleanup() {
    rm -f "${TMP_FILES[@]}" 2>/dev/null || true
}
trap cleanup EXIT

# --- 4. DOCKER COMMAND WRAPPER ---
if id -nG "$USER" | grep -qw docker || [ "$EUID" -eq 0 ]; then
    DOCKER_CMD="docker"
else
    DOCKER_CMD="sudo docker"
fi

run_cmd() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo -e "\033[1;33m[DRY RUN]\033[0m $*"
        sleep 0.3
    else
        "$@"
    fi
}

# --- PRE-FLIGHT CHECKS ---

if ! command -v dialog &> /dev/null; then
    echo "The 'dialog' tool is required but not installed."
    read -p "Install it now? [y/N]: " INSTALL_CONFIRM
    if [[ "$INSTALL_CONFIRM" =~ ^[yY] ]]; then
        if command -v apt &> /dev/null; then sudo apt update && sudo apt install -y dialog
        elif command -v pacman &> /dev/null; then sudo pacman -Sy --noconfirm dialog
        else echo "Please install 'dialog' manually."; exit 1; fi
    else exit 1; fi
fi

# --- FUNCTIONS ---

pause_prompt() {
    echo ""
    read -p "Press Enter to continue..."
}

drop_to_shell() {
    clear
    echo -e "\033[1;31m╔══════════════════════════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;37mAPP MINIMIZED:\033[0m \033[1;33mDropping to Host Shell\033[0m                                 \033[1;31m║\033[0m"
    echo -e "\033[1;31m║\033[0m \033[0;37mType '\033[1;32mexit\033[0;37m' or press \033[1;32mCtrl+D\033[0;37m to return to the Docker Manager.             \033[1;31m║\033[0m"
    echo -e "\033[1;31m╚══════════════════════════════════════════════════════════════════════════════╝\033[0m"
    echo ""
    # Launch subshell (handles mc-style "minimization")
    ${SHELL:-/bin/bash}
    clear
}

select_editor() {
    # Automatically detect editor preference (Nano > Vi) without prompting
    if command -v nano &> /dev/null; then
        echo "nano"
    elif command -v vi &> /dev/null; then
        echo "vi"
    else
        echo "vi" # Ultimate fallback
    fi
}

display_fancy_logs() {
    local name="$1"
    local mode="$2"
    local last_lines lines
    
    last_lines=$(cat "$LOG_LINES_FILE" 2>/dev/null || echo "200")
    
    # Get custom line count
    lines=$(dialog --backtitle "$BACKTITLE" --title "Log Config" \
        --stdout \
        --inputbox "How many lines to fetch?" 8 40 "$last_lines") || lines="$last_lines"

    echo "$lines" > "$LOG_LINES_FILE"

    clear
    echo -e "\033[1;31m╔══════════════════════════════════════════════════════════════════════════════╗\033[0m"
    printf "\033[1;31m║\033[0m \033[1;37mLOG DASHBOARD:\033[0m \033[1;33m%-61s\033[0m \033[1;31m║\033[0m\n" "$name"
    echo -e "\033[1;31m╠══════════════════════════════════════════════════════════════════════════════╣\033[0m"
    
    if [ "$mode" == "static" ]; then
        printf "\033[1;31m║\033[0m \033[1;34m[STATIC VIEW]\033[0m  \033[0;37mShowing last %-5s lines. Press [Enter] to return.         \033[1;31m║\033[0m\n" "$lines"
        echo -e "\033[1;31m╚══════════════════════════════════════════════════════════════════════════════╝\033[0m"
        echo ""
        $DOCKER_CMD logs --tail "$lines" "$name" 2>&1
        echo -e "\n\033[1;31m────────────────────────────────────────────────────────────────────────────────\033[0m"
        read -p "[END] Press Enter to return..."
    else
        printf "\033[1;31m║\033[0m \033[1;32m[LIVE MODE]\033[0m    \033[1;37mPress \033[1;31m[CTRL+C]\033[1;37m to stop the stream and return.             \033[1;31m║\033[0m\n"
        echo -e "\033[1;31m╚══════════════════════════════════════════════════════════════════════════════╝\033[0m"
        echo ""
        # The trap ensures we handle the exit cleanly
        $DOCKER_CMD logs -f --tail "$lines" "$name" 2>&1 || true
        echo -e "\n\033[1;31mStream stopped.\033[0m Returning..."
        sleep 1
    fi
}

enter_console() {
    local name="$1"
    local shell_choice cmd
    shell_choice=$(dialog --clear --backtitle "$BACKTITLE" --title "Console: $name" \
        --stdout \
        --menu "Select preferred shell:" 15 45 4 \
        1 "/bin/bash" \
        2 "/bin/sh" \
        3 "/bin/zsh" \
        4 "/bin/ash") || return 0
    
    case "$shell_choice" in
        1) cmd="/bin/bash" ;; 2) cmd="/bin/sh" ;; 3) cmd="/bin/zsh" ;; 4) cmd="/bin/ash" ;;
        *) cmd="/bin/sh" ;;
    esac

    clear
    $DOCKER_CMD exec -it "$name" "$cmd" || true
}

# --- CONTAINER MANAGEMENT ---

list_and_manage_containers() {
    local default_item container
    default_item=$(cat "$LAST_CONTAINER_FILE" 2>/dev/null || echo "")

    while true; do
        local menu_file
        menu_file=$(mktemp)
        TMP_FILES+=("$menu_file")
        
        $DOCKER_CMD ps -a --format '{{.Names}}|{{.Status}} ({{.Image}})' | sort > "$menu_file"
        
        local options=()
        while IFS='|' read -r name info; do
            options+=("$name" "$info")
        done < "$menu_file"

        # Use --stdout to prevent capturing empty/trash output
        container=$(dialog --clear --default-item "$default_item" \
            --backtitle "$BACKTITLE" --title "Container List" \
            --stdout \
            --menu "Select a container:" 20 85 10 "${options[@]}") || break

        echo "$container" > "$LAST_CONTAINER_FILE"
        default_item="$container"
        manage_single_container "$container" || :
    done
}

manage_single_container() {
    local name="$1"
    local is_protected=false
    local p
    
    # Protected check
    for p in "${PROTECTED_CONTAINERS[@]}"; do
        if [[ "$name" == "$p" ]]; then
            is_protected=true
        fi
    done

    while true; do
        local ip ports state health stats_raw header action log_m
        ip=$($DOCKER_CMD inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name" || echo "N/A")
        ports=$($DOCKER_CMD ps -a --filter "name=^/${name}$" --format "{{.Ports}}" || echo "None")
        state=$($DOCKER_CMD inspect -f '{{.State.Status}}' "$name")
        health=$($DOCKER_CMD inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$name" 2>/dev/null || echo "n/a")
        
        # Wrapped in bash -c to avoid sudo TTY deadlocks via timeout
        stats_raw=$(timeout 2s bash -c "$DOCKER_CMD stats --no-stream --format '{{.CPUPerc}} CPU | {{.MemUsage}} MEM' '$name'" 2>/dev/null | xargs || echo "Calculating...")
        
        header="\Z0\ZbStatus:\Zn \Z4$state\Zn (\Z4$health\Zn) | \Z0\ZbIP:\Zn \Z4$ip\Zn\n\Z0\ZbPorts:\Zn  \Z4$ports\Zn\n\Z0\ZbStats:\Zn  \Z4$stats_raw\Zn"

        action=$(dialog --clear --colors --backtitle "$BACKTITLE" --title "Manage: $name" \
            --stdout \
            --menu "$header\n\nPlease choose an action:" 20 75 9 \
            1 "Start" \
            2 "Stop" \
            3 "Restart" \
            4 "Console (Choose Shell)" \
            5 "View Logs" \
            6 "Remove Container" \
            7 "Drop to Host Shell (Minimize)" \
            8 "Back to List") || break

        case "$action" in
            1) run_cmd $DOCKER_CMD start "$name" ;;
            2) 
                if [ "$is_protected" = true ]; then
                    dialog --title "Protected" --msgbox "This is a core container ($name). Policy blocks stopping it." 6 60 2>&1 >/dev/tty
                    continue
                fi
                if dialog --title "Confirm Stop" --yesno "Stop $name?" 6 40 2>&1 >/dev/tty; then
                    run_cmd $DOCKER_CMD stop "$name"
                    pause_prompt
                fi
                ;;
            3) 
                if [ "$is_protected" = true ]; then
                    dialog --title "Protected" --msgbox "This is a core container ($name). Restarting is restricted." 6 60 2>&1 >/dev/tty
                    continue
                fi
                run_cmd $DOCKER_CMD restart "$name" 
                ;;
            4) enter_console "$name" || : ;;
            5) 
                log_m=$(dialog --stdout --menu "Log mode:" 10 40 2 1 "Live Dashboard" 2 "Static Scrollback") || continue
                [[ "$log_m" == "1" ]] && display_fancy_logs "$name" "live" || display_fancy_logs "$name" "static"
                ;;
            6)
                if [ "$is_protected" = true ]; then
                    dialog --title "Protected" --msgbox "Removal of $name is blocked by security policy." 6 50 2>&1 >/dev/tty
                    continue
                fi
                if dialog --colors --title "Confirm Removal" --yesno "\Z1\ZbDANGER:\Zn Irreversible. Remove $name?" 8 50 2>&1 >/dev/tty; then
                    run_cmd $DOCKER_CMD rm -f "$name"
                    return 0
                fi
                ;;
            7) drop_to_shell ;;
            8) return 0 ;;
        esac
    done
}

# --- CONFIG MANAGEMENT ---

find_owner_container() {
    local file_path="$1"
    # Use hardened inspect with exact matching to avoid false positives
    $DOCKER_CMD ps --format '{{.Names}}' | while read -r name; do
        if $DOCKER_CMD inspect -f '{{range .Mounts}}{{println .Source}}{{end}}' "$name" | grep -Fxq "$file_path"; then
            echo "$name"
            return 0
        fi
    done
}

perform_file_edit() {
    local file="$1"
    local editor bak pre post owner msg
    editor=$(select_editor) || return 0

    bak="${file}.$(date +%Y%m%d_%H%M%S).bak"
    
    # Check if we need sudo for the backup
    if [ -w "$(dirname "$file")" ]; then
        cp "$file" "$bak"
    else
        sudo cp "$file" "$bak"
    fi

    pre=$(sudo md5sum "$file" | awk '{print $1}')
    
    # Smart sudo logic for editing
    if [ -O "$file" ] && [ -w "$file" ]; then
        "$editor" "$file"
    else
        sudo "$editor" "$file"
    fi
    
    post=$(sudo md5sum "$file" | awk '{print $1}')

    if [ "$pre" != "$post" ]; then
        owner=$(find_owner_container "$file" || echo "")
        msg="File changed (Backup: $(basename "$bak"))."
        [[ -n "$owner" ]] && msg="${msg}\n\nRestart associated container \Z1$owner\Zn?" || msg="${msg}\n\nNo owner detected."
        
        if dialog --colors --title "Config Changed" --yesno "$msg" 12 60 2>&1 >/dev/tty; then
            if [[ -n "$owner" ]]; then
                # Apply protection check here too
                local p is_p=false
                for p in "${PROTECTED_CONTAINERS[@]}"; do [[ "$owner" == "$p" ]] && is_p=true; done
                if [ "$is_p" = true ]; then
                    dialog --msgbox "Restart for $owner blocked (Protected)." 6 50 2>&1 >/dev/tty
                else
                    run_cmd $DOCKER_CMD restart "$owner" && pause_prompt
                fi
            fi
        fi
    fi
}

# Helper to build the find command with prunes
build_find_cmd() {
    local base_path="$1"
    local max_depth="$2"
    local find_args=(sudo find "$base_path" -maxdepth "$max_depth")
    
    # Add pruning for noisy directories
    if [ "$FILTER_MODE" == "on" ]; then
        find_args+=("(")
        for i in "${!NOISE_PRUNE_DIRS[@]}"; do
            [ "$i" -gt 0 ] && find_args+=("-o")
            find_args+=("-name" "${NOISE_PRUNE_DIRS[$i]}")
        done
        find_args+=(")" "-prune" "-o")
    fi
    
    echo "${find_args[@]}"
}

run_search_for_configs() {
    local search_path="$1"
    local depth="$2"
    local out_file="$3"
    local is_dir_search="$4" # true for folder mode, false for file mode
    local err_file=$(mktemp)
    TMP_FILES+=("$err_file")

    # Build the prune arguments as an array to handle IFS safely
    local prune_args=()
    if [ "$FILTER_MODE" == "on" ]; then
        for dir in "${NOISE_PRUNE_DIRS[@]}"; do
            [ "${#prune_args[@]}" -gt 0 ] && prune_args+=("-o")
            prune_args+=("-name" "$dir")
        done
    fi

    # Fetch container mounts if needed
    local mounts=""
    if [ "$VIEW_MODE" == "associated" ]; then
        mounts=$($DOCKER_CMD inspect --format '{{range .Mounts}}{{println .Source}}{{end}}' $($DOCKER_CMD ps -a -q) 2>/dev/null | sort -u)
    fi

    local action_args=()
    if [ "$is_dir_search" = true ]; then
        action_args+=("-printf" "%h\n")
    else
        action_args+=("-type" "f")
    fi

    local count=0
    
    # We construct the full command string for eval because array expansion 
    # with nested parentheses in find is tricky in strict mode.
    # This block handles the "prune or print" logic correctly.
    {
        if [ "$FILTER_MODE" == "on" ]; then
            # The complex find command with pruning
            sudo find "$search_path" -maxdepth "$depth" \
            \( \( "${prune_args[@]}" \) -prune \) -o \
            \( \
                -name "*.yaml" -o -name "*.yml" -o -name "*.config" -o -name "*.conf" -o \
                -name "*.json" -o -name "*.toml" -o -name "*.env" -o -name "*.ini" -o -name "*.cfg" -o \
                -name "*config*.xml" -o -name "*settings*.xml" -o -name "*setup*.xml" \
            \) "${action_args[@]}"
        else
            # Simple find without pruning
            sudo find "$search_path" -maxdepth "$depth" \
            \( \
                -name "*.yaml" -o -name "*.yml" -o -name "*.config" -o -name "*.conf" -o \
                -name "*.json" -o -name "*.toml" -o -name "*.env" -o -name "*.ini" -o -name "*.cfg" -o \
                -name "*config*.xml" -o -name "*settings*.xml" -o -name "*setup*.xml" \
            \) "${action_args[@]}"
        fi
    } 2> "$err_file" | while read -r path; do
        if [ "$VIEW_MODE" == "associated" ]; then
            local matched=false
            # Case 1: Searching for folders (check if path starts with a mount or vice versa)
            if [ "$is_dir_search" = true ]; then
                echo "$mounts" | grep -q "^$path" && matched=true
            else
                # Case 2: Searching for files inside a folder.
                # If we are here, the user likely entered a valid associated folder.
                # Strictly checking if a file is a mount point hides files INSIDE mounts.
                # So we simply allow files if they are found within the valid scope.
                matched=true
            fi
            
            [ "$matched" = false ] && continue
        fi
        ((count++))
        [ $((count % 5)) -eq 0 ] && dialog --infobox "Scanning... Found $count relevant items." 5 50 2>&1 >/dev/tty
        echo "$path"
    done | sort -u > "$out_file"

    if [ ! -s "$out_file" ] && [ -s "$err_file" ]; then
        local err_msg=$(cat "$err_file" | head -n 5)
        # Only show error if it's not just "Permission denied" spam which is expected in /opt
        if [[ "$err_msg" != *"Permission denied"* ]]; then
             dialog --title "Scan Warning" --msgbox "Scan completed with errors:\n\n$err_msg" 15 70 2>&1 >/dev/tty
        fi
    fi
}

browse_config_folders() {
    local dir_list=$(mktemp)
    TMP_FILES+=("$dir_list")
    local need_scan=true
    local container_names=""

    while true; do
        if [ "$need_scan" = true ]; then
            dialog --infobox "Indexing /opt...\nMode: \Zb${VIEW_MODE}\Zn | Filter: \Zb${FILTER_MODE}\Zn" 6 50 2>&1 >/dev/tty
            run_search_for_configs "/opt" "4" "$dir_list" true
            # Optimization: Fetch container names once per scan to avoid repetitive docker calls in the loop
            container_names=$($DOCKER_CMD ps --format '{{.Names}}')
            need_scan=false
        fi

        local options=()
        local mode_label="Show All Folders"
        [ "$VIEW_MODE" == "all" ] && mode_label="Show Only Container-Associated"
        options+=("MODE" "\Z3[MODE]\Zn $mode_label")
        
        local filter_label="Disable Noise Filter"
        [ "$FILTER_MODE" == "off" ] && filter_label="Enable Noise Filter"
        options+=("FILTER" "\Z3[FILTER]\Zn $filter_label")

        while read -r dir; do
            [ -z "$dir" ] && continue
            local base=$(basename "$dir")
            # Fast check against cached container names
            if echo "$container_names" | grep -q "^${base}$"; then
                options+=("$dir" "\Z1[CONTAINER]\Zn $base") 
            else
                options+=("$dir" "$base")
            fi
        done < "$dir_list"

        local selected
        selected=$(dialog --colors --clear --backtitle "$BACKTITLE" --title "Config Folders" \
            --stdout \
            --menu "Select a folder (Cancel to return):" 20 75 10 "${options[@]}") || break

        if [ "$selected" == "MODE" ]; then
            [ "$VIEW_MODE" == "all" ] && VIEW_MODE="associated" || VIEW_MODE="all"
            need_scan=true
            continue
        elif [ "$selected" == "FILTER" ]; then
            [ "$FILTER_MODE" == "on" ] && FILTER_MODE="off" || FILTER_MODE="on"
            need_scan=true
            continue
        fi
        
        browse_files_in_dir "$selected" || :
    done
}

browse_files_in_dir() {
    local dir="$1"
    local flist=$(mktemp)
    TMP_FILES+=("$flist")
    
    dialog --infobox "Retrieving files in $(basename "$dir")..." 5 50 2>&1 >/dev/tty
    
    # Use our robust search function for files too
    run_search_for_configs "$dir" "1" "$flist" false
    
    if [ ! -s "$flist" ]; then
        dialog --msgbox "No relevant config files found in this folder." 6 50 2>&1 >/dev/tty
        return 0
    fi

    while true; do
        local options=()
        while read -r fp; do
            [ -z "$fp" ] && continue
            options+=("$fp" "$(basename "$fp")")
        done < "$flist"

        local sel
        # Use --stdout to safely capture selection and avoid empty-variable issues
        sel=$(dialog --clear --backtitle "$BACKTITLE" --title "Files: $(basename "$dir")" \
            --stdout \
            --menu "Select file (Cancel to return):" 20 75 10 "${options[@]}") || return 0

        # Only proceed if selection is not empty (prevents accidental loops)
        if [ -n "$sel" ]; then
            perform_file_edit "$sel" || :
        fi
    done
}

# --- BULK ACTIONS ---

multi_select_containers() {
    local state="off"
    local mode temp options n i selected act cmd confirm c
    mode=$(dialog --stdout --menu "Selection Mode:" 12 40 2 1 "Start Clean (None)" 2 "Select All") || return 0
    [[ "$mode" == "2" ]] && state="on"

    temp=$(mktemp)
    TMP_FILES+=("$temp")
    $DOCKER_CMD ps -a --format '{{.Names}}|{{.Status}}' | sort > "$temp"
    
    options=()
    while IFS='|' read -r n i; do
        options+=("$n" "$i" "$state")
    done < "$temp"

    selected=$(dialog --separate-output --backtitle "$BACKTITLE" --title "Multi-Action" \
        --stdout \
        --checklist "Toggle containers:" 20 75 12 "${options[@]}") || return 0

    act=$(dialog --stdout --menu "Action for $(echo "$selected" | wc -l) containers:" 15 50 4 \
        1 "Start" 2 "Stop" 3 "Restart" 4 "Remove") || return 0

    case "$act" in
        1) cmd="start"; confirm="Start these containers?" ;;
        2) cmd="stop"; confirm="STOP these containers?" ;;
        3) cmd="restart"; confirm="RESTART these containers?" ;;
        4) cmd="rm -f"; confirm="DANGER: PERMANENTLY REMOVE these containers?" ;;
    esac

    if dialog --colors --title "Confirm" --yesno "$confirm\n\n$selected" 15 65 2>&1 >/dev/tty; then
        clear
        for c in $selected; do
            echo -n "Processing $c... "
            run_cmd $DOCKER_CMD "$cmd" "$c" 
        done
        pause_prompt
    fi
}

bulk_actions() {
    while true; do
        local action=$(dialog --clear --colors --backtitle "$BACKTITLE" --title "Bulk Management" \
            --stdout \
            --menu "Actions:" 15 65 5 \
            1 "Restart ALL Running" \
            2 "Stop ALL" \
            3 "Selective Multi-Action" \
            4 "System Prune" \
            5 "Back") || break

        case "$action" in
            1) 
                local t=$($DOCKER_CMD ps -q)
                if [ -n "$t" ]; then
                    run_cmd $DOCKER_CMD restart $t && pause_prompt 
                else
                    dialog --msgbox "No running containers found." 6 40 2>&1 >/dev/tty
                fi
                ;;
            2) 
                if dialog --colors --yesno "Stop \Z1ALL\Zn containers?" 8 50 2>&1 >/dev/tty; then
                    local t=$($DOCKER_CMD ps -a -q)
                    if [ -n "$t" ]; then
                        run_cmd $DOCKER_CMD stop $t && pause_prompt
                    else
                        dialog --msgbox "No containers found." 6 40 2>&1 >/dev/tty
                    fi
                fi
                ;;
            3) multi_select_containers || : ;;
            4) 
                if dialog --colors --yesno "Prune \Z1EVERYTHING\Zn unused?" 8 50 2>&1 >/dev/tty; then
                    run_cmd $DOCKER_CMD system prune -a --volumes -f && pause_prompt
                fi
                ;;
            5) break ;;
        esac
    done
}

# --- MAIN LOOP ---

while true; do
    total=$($DOCKER_CMD ps -a -q | wc -l)
    running=$($DOCKER_CMD ps -q | wc -l)
    stopped=$((total - running))
    curr_user=$(whoami)
    curr_date=$(date "+%d-%b-%Y %H:%M")

    # The '|| continue' ensures "Cancel" or "ESC" just refreshes the dashboard.
    choice=$(dialog --colors --clear --backtitle "$BACKTITLE" --title "$TITLE" \
        --stdout \
        --menu "\n\Z0\ZbUser:\Zn   \Z4$curr_user\Zn\n\Z0\ZbDate:\Zn   \Z4$curr_date\Zn\n\Z0\ZbState:\Zn  \Z4$total\Zn (\Z2$running Up\Zn / \Z1$stopped Down\Zn)\n\nPlease choose:" \
        20 75 8 \
        1 "Container Management" \
        2 "Edit Configs (/opt)" \
        3 "Resource Monitor (stats)" \
        4 "Bulk Actions" \
        5 "Disk Usage (df)" \
        6 "Drop to Host Shell (Minimize App)" \
        7 "About / Version" \
        8 "Exit") || continue

    case "$choice" in
        1) list_and_manage_containers || : ;;
        2) browse_config_folders || : ;;
        3) clear; $DOCKER_CMD stats || : ;;
        4) bulk_actions || : ;;
        5) clear; $DOCKER_CMD system df || :; pause_prompt ;;
        6) drop_to_shell || : ;;
        7) dialog --title "About" --msgbox "Homelab Docker Manager v$SCRIPT_VERSION\nHost: $BOX\nKernel: $(uname -r)\nDocker: $($DOCKER_CMD --version)" 12 50 2>&1 >/dev/tty || : ;;
        8) clear; echo "Goodbye!"; exit 0 ;;
    esac
done
