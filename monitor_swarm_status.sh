#!/usr/bin/env bash

# ==============================================================================
# RL Swarm Multi-Instance Status Monitor
# ==============================================================================
# This script provides a real-time status dashboard for all running swarm instances
# Can be run independently from the main multi-swarm runner
# ==============================================================================

set -euo pipefail

ROOT=$PWD
LOG_BASE_DIR="$ROOT/user/logs/multi_swarm"

# ANSI color codes
GREEN_TEXT="\033[32m"
BLUE_TEXT="\033[34m"
RED_TEXT="\033[31m"
YELLOW_TEXT="\033[33m"
CYAN_TEXT="\033[36m"
MAGENTA_TEXT="\033[35m"
RESET_TEXT="\033[0m"
BOLD="\033[1m"

echo_green() { echo -e "$GREEN_TEXT$1$RESET_TEXT"; }
echo_blue() { echo -e "$BLUE_TEXT$1$RESET_TEXT"; }
echo_red() { echo -e "$RED_TEXT$1$RESET_TEXT"; }
echo_yellow() { echo -e "$YELLOW_TEXT$1$RESET_TEXT"; }
echo_cyan() { echo -e "$CYAN_TEXT$1$RESET_TEXT"; }
echo_magenta() { echo -e "$MAGENTA_TEXT$1$RESET_TEXT"; }
echo_bold() { echo -e "$BOLD$1$RESET_TEXT"; }

# Parse command line arguments
FOLLOW_MODE=${1:-""}
INSTANCE_NUM=${2:-""}

show_header() {
    clear
    echo_bold "╔════════════════════════════════════════════════════════════════════╗"
    echo_bold "║         RL-SWARM MULTI-INSTANCE STATUS DASHBOARD                  ║"
    echo_bold "╚════════════════════════════════════════════════════════════════════╝"
    echo ""
}

get_gpu_stats() {
    if command -v nvidia-smi &> /dev/null; then
        nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits
    else
        echo "N/A,N/A,N/A,N/A,N/A,N/A"
    fi
}

get_process_stats() {
    local pid=$1
    if [ -n "$pid" ] && kill -0 $pid 2>/dev/null; then
        # Get CPU and memory usage
        local stats=$(ps -p $pid -o %cpu,%mem,etime --no-headers 2>/dev/null || echo "0.0 0.0 00:00")
        echo "$stats"
    else
        echo "N/A N/A N/A"
    fi
}

find_instance_processes() {
    # Find all Python processes running swarm_launcher
    pgrep -f "rgym_exp.runner.swarm_launcher" || echo ""
}

show_gpu_info() {
    echo_cyan "┌─ GPU STATUS ──────────────────────────────────────────────────────┐"
    
    while IFS=',' read -r gpu_idx gpu_name gpu_util gpu_mem_used gpu_mem_total gpu_temp; do
        echo_green "│ GPU $gpu_idx: $gpu_name"
        echo "│   Utilization: ${gpu_util}%"
        echo "│   Memory: ${gpu_mem_used}MB / ${gpu_mem_total}MB ($(( gpu_mem_used * 100 / gpu_mem_total ))%)"
        echo "│   Temperature: ${gpu_temp}°C"
    done < <(get_gpu_stats)
    
    echo_cyan "└───────────────────────────────────────────────────────────────────┘"
    echo ""
}

show_instance_info() {
    echo_cyan "┌─ SWARM INSTANCES ─────────────────────────────────────────────────┐"
    
    local instance_count=0
    local running_count=0
    
    # Check for instance directories
    for instance_dir in "$ROOT/user"/instance_*; do
        if [ -d "$instance_dir" ]; then
            instance_count=$((instance_count + 1))
            local instance_num=$(basename "$instance_dir" | sed 's/instance_//')
            local instance_log="$LOG_BASE_DIR/instance_${instance_num}.log"
            local config_file="$instance_dir/configs/rg-swarm.yaml"
            
            echo_blue "│"
            echo_bold "│ ═══ Instance $instance_num ═══"
            
            # Find PID
            local pid=$(pgrep -f "instance_${instance_num}" | head -n 1 || echo "")
            
            if [ -n "$pid" ] && kill -0 $pid 2>/dev/null; then
                running_count=$((running_count + 1))
                echo_green "│   Status: ✓ RUNNING (PID: $pid)"
                
                # Process stats
                local stats=$(get_process_stats $pid)
                read -r cpu mem elapsed <<< "$stats"
                echo "│   CPU: ${cpu}% | Memory: ${mem}% | Uptime: $elapsed"
                
                # Log info
                if [ -f "$instance_log" ]; then
                    local log_size=$(du -h "$instance_log" | cut -f1)
                    local last_modified=$(stat -c %y "$instance_log" 2>/dev/null | cut -d'.' -f1 || stat -f "%Sm" "$instance_log" 2>/dev/null)
                    echo "│   Log: $log_size (updated: $last_modified)"
                    
                    # Show last few lines
                    echo "│   Recent activity:"
                    tail -n 3 "$instance_log" 2>/dev/null | sed 's/^/│     /' || echo "│     (no recent logs)"
                else
                    echo_yellow "│   Log: Not found"
                fi
            else
                echo_red "│   Status: ✗ NOT RUNNING"
                if [ -f "$instance_log" ]; then
                    local log_size=$(du -h "$instance_log" | cut -f1)
                    echo "│   Last log: $log_size"
                    echo "│   Last few lines:"
                    tail -n 3 "$instance_log" 2>/dev/null | sed 's/^/│     /' || echo "│     (empty log)"
                fi
            fi
            
            echo "│   Directory: $instance_dir"
            echo "│   Config: $([ -f "$config_file" ] && echo "✓" || echo "✗")"
            echo_blue "│"
        fi
    done
    
    echo_cyan "└───────────────────────────────────────────────────────────────────┘"
    echo ""
    
    if [ $instance_count -eq 0 ]; then
        echo_yellow "No instances found. Run ./run_multi_swarm.sh to create instances."
    else
        echo_bold "Summary: $running_count / $instance_count instances running"
    fi
}

show_aggregated_logs() {
    echo_cyan "┌─ RECENT LOGS (All Instances) ─────────────────────────────────────┐"
    
    if [ -d "$LOG_BASE_DIR" ]; then
        # Combine and sort recent logs from all instances
        for log_file in "$LOG_BASE_DIR"/instance_*.log; do
            if [ -f "$log_file" ]; then
                local instance_name=$(basename "$log_file" .log)
                tail -n 5 "$log_file" 2>/dev/null | sed "s/^/│ [$instance_name] /"
            fi
        done
    else
        echo "│ No logs directory found"
    fi
    
    echo_cyan "└───────────────────────────────────────────────────────────────────┘"
}

follow_instance_log() {
    local instance_num=$1
    local log_file="$LOG_BASE_DIR/instance_${instance_num}.log"
    
    if [ -f "$log_file" ]; then
        echo_cyan "Following logs for instance $instance_num (Ctrl+C to exit)"
        echo_blue "Log file: $log_file"
        echo ""
        tail -f "$log_file"
    else
        echo_red "Log file not found: $log_file"
        exit 1
    fi
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  (no args)          Show status dashboard (updates once)"
    echo "  -w, --watch        Continuous watch mode (updates every 5 seconds)"
    echo "  -f INSTANCE_NUM    Follow logs for specific instance"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                 # Show current status"
    echo "  $0 --watch         # Continuously monitor"
    echo "  $0 -f 1            # Follow instance 1 logs"
}

# Main execution
case "${FOLLOW_MODE}" in
    -h|--help)
        show_help
        ;;
    -f|--follow)
        if [ -z "$INSTANCE_NUM" ]; then
            echo_red "Error: Instance number required for follow mode"
            echo "Usage: $0 -f INSTANCE_NUM"
            exit 1
        fi
        follow_instance_log "$INSTANCE_NUM"
        ;;
    -w|--watch)
        while true; do
            show_header
            show_gpu_info
            show_instance_info
            show_aggregated_logs
            echo ""
            echo_blue "Updating in 5 seconds... (Ctrl+C to exit)"
            sleep 5
        done
        ;;
    *)
        show_header
        show_gpu_info
        show_instance_info
        show_aggregated_logs
        echo ""
        echo_blue "Tip: Use '$0 --watch' for continuous monitoring"
        echo_blue "     Use '$0 -f N' to follow instance N logs"
        ;;
esac

