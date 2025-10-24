#!/usr/bin/env bash

# ==============================================================================
# Individual Instance Controller
# ==============================================================================
# Control script for starting, stopping, and restarting individual instances
# ==============================================================================

set -euo pipefail

ROOT=$PWD
LOG_BASE_DIR="$ROOT/user/logs/multi_swarm"

# Colors
GREEN="\033[32m"
BLUE="\033[34m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

echo_green() { echo -e "$GREEN$1$RESET"; }
echo_blue() { echo -e "$BLUE$1$RESET"; }
echo_red() { echo -e "$RED$1$RESET"; }
echo_yellow() { echo -e "$YELLOW$1$RESET"; }
echo_cyan() { echo -e "$CYAN$1$RESET"; }

# ==============================================================================
# Helper Functions
# ==============================================================================

show_help() {
    cat << EOF
Usage: $0 <command> [instance_number]

Commands:
    start <N>       Start instance N
    stop <N>        Stop instance N
    restart <N>     Restart instance N
    status [N]      Show status of instance N (or all if N not provided)
    logs <N>        Show recent logs for instance N
    follow <N>      Follow logs for instance N (tail -f)
    stopall         Stop all running instances
    startall [NUM]  Start all instances (optionally specify number)
    
Examples:
    $0 start 1              # Start instance 1
    $0 stop 2               # Stop instance 2
    $0 restart 3            # Restart instance 3
    $0 status               # Show status of all instances
    $0 status 1             # Show status of instance 1
    $0 logs 1               # Show last 50 lines of instance 1
    $0 follow 2             # Follow instance 2 logs in real-time
    $0 stopall              # Stop all instances
    $0 startall 3           # Start 3 instances

EOF
}

get_instance_pid() {
    local instance_num=$1
    # Look for Python process running the specific instance
    pgrep -f "instance_${instance_num}" | head -n 1 || echo ""
}

is_instance_running() {
    local instance_num=$1
    local pid=$(get_instance_pid $instance_num)
    if [ -n "$pid" ] && kill -0 $pid 2>/dev/null; then
        return 0  # Running
    else
        return 1  # Not running
    fi
}

# ==============================================================================
# Commands
# ==============================================================================

cmd_start() {
    local instance_num=$1
    local instance_dir="$ROOT/user/instance_$instance_num"
    local instance_log="$LOG_BASE_DIR/instance_${instance_num}.log"
    
    # Check if already running
    if is_instance_running $instance_num; then
        echo_yellow "Instance $instance_num is already running (PID: $(get_instance_pid $instance_num))"
        return 1
    fi
    
    # Create directories if they don't exist
    mkdir -p "$instance_dir"/{modal-login,keys,configs,logs}
    mkdir -p "$LOG_BASE_DIR"
    
    # Copy config if it doesn't exist
    if [ ! -f "$instance_dir/configs/rg-swarm.yaml" ]; then
        if [ -f "$ROOT/rgym_exp/config/rg-swarm.yaml" ]; then
            cp "$ROOT/rgym_exp/config/rg-swarm.yaml" "$instance_dir/configs/rg-swarm.yaml"
            echo_green "Created config for instance $instance_num"
        else
            echo_red "Error: Base config not found at rgym_exp/config/rg-swarm.yaml"
            return 1
        fi
    fi
    
    # Create wrapper script
    local wrapper_script="$instance_dir/run_instance.sh"
    
    cat > "$wrapper_script" << WRAPPER_EOF
#!/usr/bin/env bash
set -euo pipefail

export INSTANCE_NUM=$instance_num
export IDENTITY_PATH="$instance_dir/keys/swarm_${instance_num}.pem"
export GENSYN_RESET_CONFIG=""
export CONNECT_TO_TESTNET=true
export ORG_ID=""
export HF_HUB_DOWNLOAD_TIMEOUT=120
export SWARM_CONTRACT="0xFaD7C5e93f28257429569B854151A1B8DCD404c2"
export PRG_CONTRACT="0x51D4db531ae706a6eC732458825465058fA23a35"
export HUGGINGFACE_ACCESS_TOKEN="${HUGGINGFACE_ACCESS_TOKEN:-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}"
export PRG_GAME=true
export ROOT="$ROOT"
export CUDA_VISIBLE_DEVICES=0

echo "=== Instance $instance_num Starting ===" >> "$instance_log"
echo "Timestamp: \$(date)" >> "$instance_log"
echo "PID: \$\$" >> "$instance_log"
echo "Identity: \$IDENTITY_PATH" >> "$instance_log"
echo "" >> "$instance_log"

cd "$ROOT"

python -m rgym_exp.runner.swarm_launcher \\
    --config-path "$instance_dir/configs" \\
    --config-name "rg-swarm.yaml" \\
    >> "$instance_log" 2>&1
WRAPPER_EOF
    
    chmod +x "$wrapper_script"
    
    # Start in background
    echo_blue "Starting instance $instance_num..."
    nohup bash "$wrapper_script" &> /dev/null &
    local pid=$!
    
    sleep 2
    
    # Verify it started
    if kill -0 $pid 2>/dev/null; then
        echo_green "✓ Instance $instance_num started successfully (PID: $pid)"
        echo_blue "  Log: $instance_log"
        echo_blue "  Config: $instance_dir/configs/rg-swarm.yaml"
        return 0
    else
        echo_red "✗ Instance $instance_num failed to start"
        echo "  Check logs: tail -f $instance_log"
        return 1
    fi
}

cmd_stop() {
    local instance_num=$1
    local pid=$(get_instance_pid $instance_num)
    
    if [ -z "$pid" ]; then
        echo_yellow "Instance $instance_num is not running"
        return 1
    fi
    
    echo_blue "Stopping instance $instance_num (PID: $pid)..."
    
    # Try graceful shutdown first
    kill -TERM $pid 2>/dev/null || true
    
    # Wait up to 15 seconds
    for i in {1..15}; do
        if ! kill -0 $pid 2>/dev/null; then
            echo_green "✓ Instance $instance_num stopped gracefully"
            return 0
        fi
        sleep 1
    done
    
    # Force kill
    echo_yellow "Graceful shutdown timed out, force killing..."
    kill -KILL $pid 2>/dev/null || true
    sleep 1
    
    if ! kill -0 $pid 2>/dev/null; then
        echo_yellow "✓ Instance $instance_num force stopped"
        return 0
    else
        echo_red "✗ Failed to stop instance $instance_num"
        return 1
    fi
}

cmd_restart() {
    local instance_num=$1
    
    echo_cyan "Restarting instance $instance_num..."
    
    # Stop if running
    if is_instance_running $instance_num; then
        cmd_stop $instance_num
        sleep 2
    fi
    
    # Start
    cmd_start $instance_num
}

cmd_status() {
    local instance_num=${1:-""}
    
    if [ -n "$instance_num" ]; then
        # Show specific instance
        show_instance_status $instance_num
    else
        # Show all instances
        echo_cyan "=== All Instances Status ==="
        echo ""
        
        local found_any=false
        for i in {1..10}; do
            if [ -d "$ROOT/user/instance_$i" ]; then
                found_any=true
                show_instance_status $i
                echo ""
            fi
        done
        
        if [ "$found_any" = false ]; then
            echo_yellow "No instances found"
            echo "Run: $0 start <N> to create and start an instance"
        fi
    fi
}

show_instance_status() {
    local instance_num=$1
    local instance_dir="$ROOT/user/instance_$instance_num"
    local instance_log="$LOG_BASE_DIR/instance_${instance_num}.log"
    
    if [ ! -d "$instance_dir" ]; then
        echo_red "Instance $instance_num: Not configured"
        return
    fi
    
    echo_cyan "─── Instance $instance_num ───"
    
    if is_instance_running $instance_num; then
        local pid=$(get_instance_pid $instance_num)
        echo_green "Status: ✓ RUNNING (PID: $pid)"
        
        # CPU and memory
        local stats=$(ps -p $pid -o %cpu,%mem,etime --no-headers 2>/dev/null || echo "N/A N/A N/A")
        read -r cpu mem uptime <<< "$stats"
        echo "CPU: ${cpu}% | Memory: ${mem}% | Uptime: $uptime"
        
        # Log info
        if [ -f "$instance_log" ]; then
            local log_size=$(du -h "$instance_log" | cut -f1)
            local last_update=$(stat -c %y "$instance_log" 2>/dev/null | cut -d'.' -f1 || stat -f "%Sm" "$instance_log" 2>/dev/null)
            echo "Log: $log_size (updated: $last_update)"
        fi
    else
        echo_red "Status: ✗ NOT RUNNING"
        
        if [ -f "$instance_log" ]; then
            local log_size=$(du -h "$instance_log" | cut -f1)
            echo "Last log: $log_size"
            
            # Show last error if exists
            if grep -q "error\|Error\|ERROR" "$instance_log" 2>/dev/null; then
                echo_yellow "Last error:"
                grep -i "error" "$instance_log" | tail -n 1 | sed 's/^/  /'
            fi
        fi
    fi
    
    echo "Directory: $instance_dir"
    echo "Config: $([ -f "$instance_dir/configs/rg-swarm.yaml" ] && echo "✓" || echo "✗")"
}

cmd_logs() {
    local instance_num=$1
    local lines=${2:-50}
    local instance_log="$LOG_BASE_DIR/instance_${instance_num}.log"
    
    if [ ! -f "$instance_log" ]; then
        echo_red "No log file found for instance $instance_num"
        echo "Expected: $instance_log"
        return 1
    fi
    
    echo_cyan "Last $lines lines from instance $instance_num:"
    echo_blue "────────────────────────────────────────────────"
    tail -n $lines "$instance_log"
}

cmd_follow() {
    local instance_num=$1
    local instance_log="$LOG_BASE_DIR/instance_${instance_num}.log"
    
    if [ ! -f "$instance_log" ]; then
        echo_red "No log file found for instance $instance_num"
        echo "Expected: $instance_log"
        return 1
    fi
    
    echo_cyan "Following logs for instance $instance_num (Ctrl+C to exit)"
    echo_blue "File: $instance_log"
    echo ""
    tail -f "$instance_log"
}

cmd_stopall() {
    echo_cyan "Stopping all instances..."
    echo ""
    
    local stopped=0
    for i in {1..10}; do
        if is_instance_running $i; then
            cmd_stop $i
            stopped=$((stopped + 1))
            echo ""
        fi
    done
    
    if [ $stopped -eq 0 ]; then
        echo_yellow "No running instances found"
    else
        echo_green "Stopped $stopped instance(s)"
    fi
}

cmd_startall() {
    local num_instances=${1:-3}
    
    echo_cyan "Starting $num_instances instances..."
    echo ""
    
    for i in $(seq 1 $num_instances); do
        cmd_start $i
        echo ""
        sleep 3  # Stagger starts
    done
    
    echo_green "Started $num_instances instances"
    echo_blue "Monitor with: $0 status"
}

# ==============================================================================
# Main
# ==============================================================================

COMMAND=${1:-""}
INSTANCE_NUM=${2:-""}

case "$COMMAND" in
    start)
        if [ -z "$INSTANCE_NUM" ]; then
            echo_red "Error: Instance number required"
            echo "Usage: $0 start <instance_number>"
            exit 1
        fi
        cmd_start $INSTANCE_NUM
        ;;
    stop)
        if [ -z "$INSTANCE_NUM" ]; then
            echo_red "Error: Instance number required"
            echo "Usage: $0 stop <instance_number>"
            exit 1
        fi
        cmd_stop $INSTANCE_NUM
        ;;
    restart)
        if [ -z "$INSTANCE_NUM" ]; then
            echo_red "Error: Instance number required"
            echo "Usage: $0 restart <instance_number>"
            exit 1
        fi
        cmd_restart $INSTANCE_NUM
        ;;
    status)
        cmd_status $INSTANCE_NUM
        ;;
    logs)
        if [ -z "$INSTANCE_NUM" ]; then
            echo_red "Error: Instance number required"
            echo "Usage: $0 logs <instance_number> [lines]"
            exit 1
        fi
        LINES=${3:-50}
        cmd_logs $INSTANCE_NUM $LINES
        ;;
    follow)
        if [ -z "$INSTANCE_NUM" ]; then
            echo_red "Error: Instance number required"
            echo "Usage: $0 follow <instance_number>"
            exit 1
        fi
        cmd_follow $INSTANCE_NUM
        ;;
    stopall)
        cmd_stopall
        ;;
    startall)
        NUM=${INSTANCE_NUM:-3}
        cmd_startall $NUM
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        echo_red "Unknown command: $COMMAND"
        echo ""
        show_help
        exit 1
        ;;
esac

