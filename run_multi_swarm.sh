#!/usr/bin/env bash

set -euo pipefail

# ==============================================================================
# Multi-Instance RL Swarm Runner
# ==============================================================================
# This script manages multiple parallel RL swarm training instances to maximize
# GPU utilization. Designed for GPUs with 24GB memory (like RTX 4090).
#
# Features:
# - Runs 2-3 parallel instances based on available GPU memory
# - Monitors GPU usage, logs, and Docker containers
# - Automatic health checks and restart capabilities
# - Separate log files for each instance
# - Graceful shutdown handling
# ==============================================================================

ROOT=$PWD

# Configuration
NUM_INSTANCES=${NUM_INSTANCES:-3}  # Number of parallel instances (2-3 recommended for 24GB GPU)
USE_DOCKER=${USE_DOCKER:-"yes"}    # "yes" or "no"
GPU_MEMORY_PER_INSTANCE=${GPU_MEMORY_PER_INSTANCE:-8000}  # MB per instance (conservative estimate)
MONITOR_INTERVAL=${MONITOR_INTERVAL:-60}  # Seconds between monitoring checks
AUTO_RESTART=${AUTO_RESTART:-"yes"}  # Auto-restart failed instances
LOG_BASE_DIR="$ROOT/user/logs/multi_swarm"

# ANSI color codes
GREEN_TEXT="\033[32m"
BLUE_TEXT="\033[34m"
RED_TEXT="\033[31m"
YELLOW_TEXT="\033[33m"
CYAN_TEXT="\033[36m"
RESET_TEXT="\033[0m"

# Arrays to track instances
declare -a INSTANCE_PIDS=()
declare -a INSTANCE_NAMES=()
declare -a INSTANCE_PORTS=()
declare -a INSTANCE_LOGS=()

echo_green() {
    echo -e "$GREEN_TEXT$1$RESET_TEXT"
}

echo_blue() {
    echo -e "$BLUE_TEXT$1$RESET_TEXT"
}

echo_red() {
    echo -e "$RED_TEXT$1$RESET_TEXT"
}

echo_yellow() {
    echo -e "$YELLOW_TEXT$1$RESET_TEXT"
}

echo_cyan() {
    echo -e "$CYAN_TEXT$1$RESET_TEXT"
}

# ==============================================================================
# Banner
# ==============================================================================
echo -e "\033[38;5;224m"
cat << "EOF"
    ███    ███ ██    ██ ██      ████████ ██       ███████ ██     ██  █████  ██████  ███    ███
    ████  ████ ██    ██ ██         ██    ██       ██      ██     ██ ██   ██ ██   ██ ████  ████
    ██ ████ ██ ██    ██ ██         ██    ██ █████ ███████ ██  █  ██ ███████ ██████  ██ ████ ██
    ██  ██  ██ ██    ██ ██         ██    ██            ██ ██ ███ ██ ██   ██ ██   ██ ██  ██  ██
    ██      ██  ██████  ███████    ██    ██       ███████  ███ ███  ██   ██ ██   ██ ██      ██

    Multi-Instance Parallel Training Manager
    From Gensyn

EOF
echo -e "$RESET_TEXT"

# ==============================================================================
# Pre-flight checks
# ==============================================================================
check_gpu_available() {
    if command -v nvidia-smi &> /dev/null; then
        GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -n 1)
        GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1)
        echo_green "✓ Detected $GPU_COUNT GPU(s) with ${GPU_MEMORY}MB total memory"
        
        # Calculate max instances based on memory
        MAX_INSTANCES=$((GPU_MEMORY / GPU_MEMORY_PER_INSTANCE))
        if [ $NUM_INSTANCES -gt $MAX_INSTANCES ]; then
            echo_yellow "⚠ Warning: Requested $NUM_INSTANCES instances but only $MAX_INSTANCES recommended"
            echo_yellow "  Proceeding with $NUM_INSTANCES as requested. Monitor GPU memory carefully."
        fi
        return 0
    else
        echo_red "✗ nvidia-smi not found. Cannot detect GPU."
        return 1
    fi
}

check_docker_available() {
    if [ "$USE_DOCKER" = "yes" ]; then
        if ! command -v docker &> /dev/null; then
            echo_red "✗ Docker not found but USE_DOCKER=yes"
            return 1
        fi
        if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
            echo_red "✗ docker-compose not found"
            return 1
        fi
        echo_green "✓ Docker available"
    fi
    return 0
}

# ==============================================================================
# Setup
# ==============================================================================
setup_directories() {
    echo_blue "Setting up directories for $NUM_INSTANCES instances..."
    
    mkdir -p "$LOG_BASE_DIR"
    
    for i in $(seq 1 $NUM_INSTANCES); do
        INSTANCE_DIR="$ROOT/user/instance_$i"
        mkdir -p "$INSTANCE_DIR"/{modal-login,keys,configs,logs}
        
        # Copy base config if it doesn't exist
        if [ ! -f "$INSTANCE_DIR/configs/rg-swarm.yaml" ]; then
            if [ -f "$ROOT/rgym_exp/config/rg-swarm.yaml" ]; then
                cp "$ROOT/rgym_exp/config/rg-swarm.yaml" "$INSTANCE_DIR/configs/rg-swarm.yaml"
            fi
        fi
        
        INSTANCE_NAMES+=("swarm_instance_$i")
        INSTANCE_PORTS+=($((3000 + i - 1)))  # Ports 3000, 3001, 3002, etc.
        INSTANCE_LOGS+=("$LOG_BASE_DIR/instance_${i}.log")
        
        echo_green "  Created instance_$i (port ${INSTANCE_PORTS[$((i-1))]})"
    done
}

# ==============================================================================
# Instance Management
# ==============================================================================
start_instance() {
    local instance_num=$1
    local instance_idx=$((instance_num - 1))
    local instance_name="${INSTANCE_NAMES[$instance_idx]}"
    local instance_port="${INSTANCE_PORTS[$instance_idx]}"
    local instance_log="${INSTANCE_LOGS[$instance_idx]}"
    local instance_dir="$ROOT/user/instance_$instance_num"
    
    echo_cyan "▶ Starting instance $instance_num on port $instance_port..."
    
    # Create a wrapper script for this instance
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
export HUGGINGFACE_ACCESS_TOKEN="${HUGGINGFACE_ACCESS_TOKEN:-}"
export PRG_GAME=true
export ROOT="$ROOT"
export CUDA_VISIBLE_DEVICES=0  # All instances share the same GPU

# Log environment
echo "=== Instance $instance_num Starting ===" >> "$instance_log"
echo "Timestamp: \$(date)" >> "$instance_log"
echo "PID: \$\$" >> "$instance_log"
echo "Identity: \$IDENTITY_PATH" >> "$instance_log"
echo "Port: $instance_port" >> "$instance_log"
echo "" >> "$instance_log"

cd "$ROOT"

# Run the actual training (simplified version without interactive prompts)
python -m rgym_exp.runner.swarm_launcher \\
    --config-path "$instance_dir/configs" \\
    --config-name "rg-swarm.yaml" \\
    >> "$instance_log" 2>&1
WRAPPER_EOF
    
    chmod +x "$wrapper_script"
    
    # Start the instance in background
    if [ "$USE_DOCKER" = "yes" ]; then
        # Docker mode (more complex, keeping simple for now)
        bash "$wrapper_script" &
        local pid=$!
    else
        # Direct execution mode
        bash "$wrapper_script" &
        local pid=$!
    fi
    
    INSTANCE_PIDS[$instance_idx]=$pid
    
    echo_green "  ✓ Instance $instance_num started (PID: $pid)"
    echo_blue "    Log: $instance_log"
}

stop_instance() {
    local instance_num=$1
    local instance_idx=$((instance_num - 1))
    local pid="${INSTANCE_PIDS[$instance_idx]}"
    
    if [ -n "$pid" ] && kill -0 $pid 2>/dev/null; then
        echo_yellow "◼ Stopping instance $instance_num (PID: $pid)..."
        kill -TERM $pid 2>/dev/null || true
        
        # Wait up to 10 seconds for graceful shutdown
        for i in {1..10}; do
            if ! kill -0 $pid 2>/dev/null; then
                echo_green "  ✓ Instance $instance_num stopped gracefully"
                return 0
            fi
            sleep 1
        done
        
        # Force kill if still running
        kill -KILL $pid 2>/dev/null || true
        echo_yellow "  ⚠ Instance $instance_num force-killed"
    else
        echo_yellow "  Instance $instance_num not running"
    fi
}

# ==============================================================================
# Monitoring
# ==============================================================================
monitor_gpu_usage() {
    if command -v nvidia-smi &> /dev/null; then
        local gpu_usage=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits | head -n 1)
        echo "$gpu_usage"
    else
        echo "N/A,N/A,N/A"
    fi
}

check_instance_health() {
    local instance_num=$1
    local instance_idx=$((instance_num - 1))
    local pid="${INSTANCE_PIDS[$instance_idx]}"
    local instance_log="${INSTANCE_LOGS[$instance_idx]}"
    
    # Check if process is running
    if [ -z "$pid" ] || ! kill -0 $pid 2>/dev/null; then
        return 1  # Not running
    fi
    
    # Check for recent errors in log (optional, can be enhanced)
    if [ -f "$instance_log" ]; then
        local recent_errors=$(tail -n 50 "$instance_log" | grep -i "error\|exception\|failed" | wc -l)
        if [ $recent_errors -gt 10 ]; then
            return 2  # Running but unhealthy
        fi
    fi
    
    return 0  # Healthy
}

monitor_loop() {
    echo_blue "Starting monitoring loop (interval: ${MONITOR_INTERVAL}s)..."
    echo_blue "Press Ctrl+C to stop all instances and exit"
    echo ""
    
    local iteration=0
    
    while true; do
        iteration=$((iteration + 1))
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        
        echo_cyan "=== Monitor Check #$iteration at $timestamp ==="
        
        # GPU stats
        local gpu_stats=$(monitor_gpu_usage)
        IFS=',' read -r gpu_util gpu_mem_used gpu_mem_total <<< "$gpu_stats"
        echo "GPU: ${gpu_util}% utilization | Memory: ${gpu_mem_used}MB / ${gpu_mem_total}MB"
        
        # Check each instance
        for i in $(seq 1 $NUM_INSTANCES); do
            local instance_idx=$((i - 1))
            local pid="${INSTANCE_PIDS[$instance_idx]}"
            local instance_log="${INSTANCE_LOGS[$instance_idx]}"
            
            check_instance_health $i
            local health_status=$?
            
            case $health_status in
                0)
                    echo_green "  ✓ Instance $i: HEALTHY (PID: $pid)"
                    # Show last log line
                    if [ -f "$instance_log" ]; then
                        local last_line=$(tail -n 1 "$instance_log" | cut -c 1-100)
                        echo "    Last: $last_line"
                    fi
                    ;;
                1)
                    echo_red "  ✗ Instance $i: NOT RUNNING"
                    if [ "$AUTO_RESTART" = "yes" ]; then
                        echo_yellow "    Attempting restart..."
                        start_instance $i
                    fi
                    ;;
                2)
                    echo_yellow "  ⚠ Instance $i: RUNNING BUT UNHEALTHY (PID: $pid)"
                    ;;
            esac
        done
        
        echo ""
        sleep $MONITOR_INTERVAL
    done
}

# ==============================================================================
# Cleanup
# ==============================================================================
cleanup() {
    echo ""
    echo_yellow "=== Shutdown signal received ==="
    
    for i in $(seq 1 $NUM_INSTANCES); do
        stop_instance $i
    done
    
    echo_green "=== All instances stopped ==="
    echo_blue "Logs available at: $LOG_BASE_DIR"
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# ==============================================================================
# Main Execution
# ==============================================================================
main() {
    echo_blue "=== Multi-Instance RL Swarm Configuration ==="
    echo "Number of instances: $NUM_INSTANCES"
    echo "Use Docker: $USE_DOCKER"
    echo "GPU memory per instance: ${GPU_MEMORY_PER_INSTANCE}MB"
    echo "Monitor interval: ${MONITOR_INTERVAL}s"
    echo "Auto-restart: $AUTO_RESTART"
    echo "Log directory: $LOG_BASE_DIR"
    echo ""
    
    # Pre-flight checks
    echo_blue "=== Pre-flight Checks ==="
    if ! check_gpu_available; then
        echo_red "GPU check failed. Exiting."
        exit 1
    fi
    
    if ! check_docker_available; then
        echo_red "Docker check failed. Exiting."
        exit 1
    fi
    
    echo ""
    
    # Setup
    setup_directories
    echo ""
    
    # Start all instances
    echo_blue "=== Starting $NUM_INSTANCES Instances ==="
    for i in $(seq 1 $NUM_INSTANCES); do
        start_instance $i
        sleep 5  # Stagger starts to avoid resource conflicts
    done
    echo ""
    
    sleep 5
    
    # Enter monitoring loop
    monitor_loop
}

# Run main
main

