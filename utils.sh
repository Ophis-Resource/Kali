#!/bin/bash

print_star_box2() {
    local content=("$@")
    local max_length=0
    for line in "${content[@]}"; do
        (( ${#line} > max_length )) && max_length=${#line}
    done
    local box_width=$((max_length + 4))
    for ((i=0; i<box_width; i++)); do echo -n "*"; done; echo
    for line in "${content[@]}"; do printf "* %-${max_length}s *\n" "$line"; done
    for ((i=0; i<box_width; i++)); do echo -n "*"; done; echo
}

print_separator() {
    echo "======================================================================================"
    echo "Timestamp: $(date +'%Y-%m-%d %H:%M:%S')"
    echo "======================================================================================"
}

print_separator2() {
    echo "======================================================================================"
}

run_command() {
    local command=$1
    local description=$2
    echo -e "\n[*] Running: $description"
    eval "$command" 2>&1 | tee -a "$LOGFILE"
}
