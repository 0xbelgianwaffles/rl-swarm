#!/usr/bin/env bash

set -euo pipefail

# ==============================================================================
# 8-Pod Multi-GPU RL Swarm Runner - AUTOMATED
# ==============================================================================
# This wrapper manages 8 separate multi-swarm instances, one per GPU
# Each GPU runs up to 3 swarm instances (24 total instances across 8 GPUs)
# Perfect for 8x RTX 4090 setups
# ==============================================================================

ROOT=$PWD

# Configuration for 8-GPU setup
NUM_GPUS=${NUM_GPUS:-8}
INSTANCES_PER_GPU=${INSTANCES_PER_GPU:-3}
GPU_MEMORY_PER_INSTANCE=${GPU_MEMORY_PER_INSTANCE:-8000}
MONITOR_INTERVAL=${MONITOR_INTERVAL:-60}
AUTO_RESTART=${AUTO_RESTART:-"yes"}
LOG_BASE_DIR="$ROOT/user/logs/8pod_swarm"

# Path to the single-GPU multi-swarm script
MULTI_SWARM_SCRIPT="$ROOT/run_multi_swarm_auto.sh"

# Credentials - will be passed to each GPU instance
export EXISTING_CREDENTIALS="/root/userData.json"
export ORG_ID="b7b8ac33-4087-497b-a5f1-02ffe32fa29e"
export WALLET_ADDRESS="0xF604Da031cE1354c8036C91766adaf669Fc7AAD0"
export CONNECT_TO_TESTNET=true
export SWARM_CONTRACT="0xFaD7C5e93f28257429569B854151A1B8DCD404c2"
export PRG_CONTRACT="0x51D4db531ae706a6eC732458825465058fA23a35"
export HUGGINGFACE_ACCESS_TOKEN="${HUGGINGFACE_ACCESS_TOKEN:-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}"
export PRG_GAME=true
export HF_HUB_DOWNLOAD_TIMEOUT=120
export AUTO_RESTART
export GPU_MEMORY_PER_INSTANCE

# ANSI colors
GREEN_TEXT="\033[32m"
BLUE_TEXT="\033[34m"
RED_TEXT="\033[31m"
YELLOW_TEXT="\033[33m"
CYAN_TEXT="\033[36m"
MAGENTA_TEXT="\033[35m"
RESET_TEXT="\033[0m"

declare -a GPU_PIDS=()
declare -a GPU_LOGS=()

echo_green() { echo -e "$GREEN_TEXT$1$RESET_TEXT"; }
echo_blue() { echo -e "$BLUE_TEXT$1$RESET_TEXT"; }
echo_red() { echo -e "$RED_TEXT$1$RESET_TEXT"; }
echo_yellow() { echo -e "$YELLOW_TEXT$1$RESET_TEXT"; }
echo_cyan() { echo -e "$CYAN_TEXT$1$RESET_TEXT"; }
echo_magenta() { echo -e "$MAGENTA_TEXT$1$RESET_TEXT"; }

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

    8x GPU Multi-Instance Training - AUTOMATED MODE
    Total Capacity: 8 GPUs x 3 instances = 24 parallel swarm instances
    Using credentials from $EXISTING_CREDENTIALS

EOF
echo -e "$RESET_TEXT"

# ==============================================================================
# Validation
# ==============================================================================
validate_environment() {
    echo_blue "=== Validating Environment ==="
    
    # Check for the multi-swarm script
    if [ ! -f "$MULTI_SWARM_SCRIPT" ]; then
        echo_red "✗ Multi-swarm script not found: $MULTI_SWARM_SCRIPT"
        exit 1
    fi
    echo_green "✓ Found multi-swarm script: $MULTI_SWARM_SCRIPT"
    
    # Check credentials
    if [ ! -f "$EXISTING_CREDENTIALS" ]; then
        echo_red "✗ Credentials not found: $EXISTING_CREDENTIALS"
        echo_yellow "Please run ./run_rl_swarm.sh once to authenticate"
        exit 1
    fi
    echo_green "✓ Found credentials: $EXISTING_CREDENTIALS"
    echo "  ORG_ID: $ORG_ID"
    echo "  Wallet: $WALLET_ADDRESS"
    
    # Check GPU count
    if command -v nvidia-smi &> /dev/null; then
        DETECTED_GPUS=$(nvidia-smi --list-gpus | wc -l)
        echo_green "✓ Detected $DETECTED_GPUS GPU(s)"
        
        if [ $DETECTED_GPUS -lt $NUM_GPUS ]; then
            echo_yellow "⚠ Warning: Detected $DETECTED_GPUS GPUs, but configured for $NUM_GPUS"
            echo_yellow "  Will only use $DETECTED_GPUS GPUs"
            NUM_GPUS=$DETECTED_GPUS
        fi
        
        # Show GPU info
        echo_cyan "GPU Information:"
        nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader | while IFS=',' read -r idx name mem; do
            echo "  GPU $idx: $name -$mem"
        done
    else
        echo_red "✗ nvidia-smi not found. Cannot detect GPUs."
        exit 1
    fi
    
    echo ""
}

# ==============================================================================
# Setup
# ==============================================================================
setup_directories() {
    echo_blue "=== Setting Up Directory Structure ==="
    
    mkdir -p "$LOG_BASE_DIR"
    
    for gpu_id in $(seq 0 $((NUM_GPUS - 1))); do
        local gpu_log="$LOG_BASE_DIR/gpu_${gpu_id}.log"
        GPU_LOGS+=("$gpu_log")
        echo_green "  GPU $gpu_id → $gpu_log"
    done
    
    echo ""
}

# ==============================================================================
# GPU Instance Management (Each GPU runs a separate multi-swarm script)
# ==============================================================================
start_gpu_swarm() {
    local gpu_id=$1
    local gpu_log="${GPU_LOGS[$gpu_id]}"
    
    # Calculate instance numbering for this GPU
    # GPU 0: instances 1-3, GPU 1: instances 4-6, etc.
    local base_instance=$((gpu_id * INSTANCES_PER_GPU + 1))
    
    echo_cyan "▶ Starting GPU $gpu_id swarm (instances $base_instance-$((base_instance + INSTANCES_PER_GPU - 1)))..."
    
    # Launch run_multi_swarm_auto.sh for this GPU
    (
        export CUDA_VISIBLE_DEVICES=$gpu_id
        export NUM_INSTANCES=$INSTANCES_PER_GPU
        export LOG_BASE_DIR="$ROOT/user/logs/gpu_${gpu_id}"
        export MONITOR_INTERVAL=$MONITOR_INTERVAL
        
        # Offset instance directories to avoid conflicts
        # We'll modify the script call to use gpu-specific paths
        cd "$ROOT"
        
        echo "=== GPU $gpu_id Multi-Swarm Starting ===" >> "$gpu_log"
        echo "Timestamp: $(date)" >> "$gpu_log"
        echo "CUDA_VISIBLE_DEVICES: $gpu_id" >> "$gpu_log"
        echo "Instances on this GPU: $INSTANCES_PER_GPU" >> "$gpu_log"
        echo "Base instance number: $base_instance" >> "$gpu_log"
        echo "" >> "$gpu_log"
        
        # Create a custom user directory for this GPU's instances
        export GPU_USER_DIR="$ROOT/user/gpu_${gpu_id}"
        mkdir -p "$GPU_USER_DIR"
        
        # Run the multi-swarm script with GPU-specific settings
        bash "$MULTI_SWARM_SCRIPT" >> "$gpu_log" 2>&1
    ) &
    
    local pid=$!
    GPU_PIDS[$gpu_id]=$pid
    
    sleep 3
    
    if kill -0 $pid 2>/dev/null; then
        echo_green "  ✓ GPU $gpu_id swarm started (PID: $pid)"
        echo_blue "    Log: $gpu_log"
        echo_blue "    Managing $INSTANCES_PER_GPU instances"
    else
        echo_red "  ✗ GPU $gpu_id swarm failed to start"
    fi
}

stop_gpu_swarm() {
    local gpu_id=$1
    local pid="${GPU_PIDS[$gpu_id]}"
    
    if [ -n "$pid" ] && kill -0 $pid 2>/dev/null; then
        echo_yellow "◼ Stopping GPU $gpu_id swarm (PID: $pid)..."
        
        # Send SIGTERM to the entire process group
        kill -TERM -$pid 2>/dev/null || true
        
        # Wait for graceful shutdown
        for i in {1..15}; do
            if ! kill -0 $pid 2>/dev/null; then
                echo_green "  ✓ GPU $gpu_id swarm stopped"
                return 0
            fi
            sleep 1
        done
        
        # Force kill if necessary
        kill -KILL -$pid 2>/dev/null || true
        echo_yellow "  ⚠ GPU $gpu_id swarm force-killed"
    fi
}

# ==============================================================================
# Monitoring
# ==============================================================================
check_gpu_swarm_health() {
    local gpu_id=$1
    local pid="${GPU_PIDS[$gpu_id]}"
    
    if [ -z "$pid" ] || ! kill -0 $pid 2>/dev/null; then
        return 1
    fi
    return 0
}

monitor_loop() {
    echo_magenta "╔════════════════════════════════════════════════════════════════╗"
    echo_magenta "║   8-POD MONITOR - Tracking $((NUM_GPUS * INSTANCES_PER_GPU)) total swarm instances          ║"
    echo_magenta "╚════════════════════════════════════════════════════════════════╝"
    echo_blue "Monitor interval: ${MONITOR_INTERVAL}s | Auto-restart: $AUTO_RESTART"
    echo_blue "Press Ctrl+C to stop all GPU swarms and exit"
    echo ""
    
    local iteration=0
    
    while true; do
        iteration=$((iteration + 1))
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        
        echo_cyan "╔═══════════════════════════════════════════════════════════════╗"
        echo_cyan "║ Monitor Check #$iteration at $timestamp"
        echo_cyan "╚═══════════════════════════════════════════════════════════════╝"
        
        # Get GPU stats for all GPUs
        if command -v nvidia-smi &> /dev/null; then
            echo_yellow "GPU Status:"
            nvidia-smi --query-gpu=index,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits | while IFS=',' read -r idx util mem_used mem_total temp; do
                printf "  GPU %d: %3d%% util | %5dMB / %5dMB | %2d°C\n" "$idx" "$util" "$mem_used" "$mem_total" "$temp"
            done
            echo ""
        fi
        
        # Check each GPU swarm
        echo_yellow "GPU Swarm Health:"
        for gpu_id in $(seq 0 $((NUM_GPUS - 1))); do
            local pid="${GPU_PIDS[$gpu_id]}"
            local gpu_log="${GPU_LOGS[$gpu_id]}"
            
            if check_gpu_swarm_health $gpu_id; then
                echo_green "  ✓ GPU $gpu_id: HEALTHY (PID: $pid, $INSTANCES_PER_GPU instances)"
                
                # Show recent activity from log
                if [ -f "$gpu_log" ]; then
                    local last_line=$(tail -n 3 "$gpu_log" 2>/dev/null | head -n 1 | cut -c 1-70 || echo "")
                    [ -n "$last_line" ] && echo "    → $last_line"
                fi
            else
                echo_red "  ✗ GPU $gpu_id: NOT RUNNING"
                if [ "$AUTO_RESTART" = "yes" ]; then
                    echo_yellow "    ⟳ Attempting restart..."
                    start_gpu_swarm $gpu_id
                fi
            fi
        done
        
        # Summary
        local healthy_count=0
        for gpu_id in $(seq 0 $((NUM_GPUS - 1))); do
            if check_gpu_swarm_health $gpu_id; then
                healthy_count=$((healthy_count + 1))
            fi
        done
        
        local total_instances=$((healthy_count * INSTANCES_PER_GPU))
        echo ""
        echo_cyan "Summary: $healthy_count/$NUM_GPUS GPU swarms healthy → ~$total_instances active swarm instances"
        echo ""
        
        sleep $MONITOR_INTERVAL
    done
}

# ==============================================================================
# Cleanup
# ==============================================================================
cleanup() {
    echo ""
    echo_yellow "╔════════════════════════════════════════════════════════════════╗"
    echo_yellow "║            SHUTDOWN SIGNAL RECEIVED                            ║"
    echo_yellow "╚════════════════════════════════════════════════════════════════╝"
    
    echo_cyan "Stopping all GPU swarms gracefully..."
    
    for gpu_id in $(seq 0 $((NUM_GPUS - 1))); do
        stop_gpu_swarm $gpu_id
    done
    
    echo ""
    echo_green "╔════════════════════════════════════════════════════════════════╗"
    echo_green "║          ALL GPU SWARMS STOPPED SUCCESSFULLY                   ║"
    echo_green "╚════════════════════════════════════════════════════════════════╝"
    echo_blue "Master log directory: $LOG_BASE_DIR"
    echo_blue "GPU-specific logs: $LOG_BASE_DIR/gpu_*.log"
    echo ""
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# ==============================================================================
# Main
# ==============================================================================
main() {
    echo_magenta "╔════════════════════════════════════════════════════════════════╗"
    echo_magenta "║            8-POD CONFIGURATION                                  ║"
    echo_magenta "╚════════════════════════════════════════════════════════════════╝"
    echo "GPUs: $NUM_GPUS"
    echo "Instances per GPU: $INSTANCES_PER_GPU"
    echo "Total instances: $((NUM_GPUS * INSTANCES_PER_GPU))"
    echo "GPU memory per instance: ${GPU_MEMORY_PER_INSTANCE}MB"
    echo "Monitor interval: ${MONITOR_INTERVAL}s"
    echo "Auto-restart: $AUTO_RESTART"
    echo "ORG_ID: $ORG_ID"
    echo "Master log directory: $LOG_BASE_DIR"
    echo ""
    
    # Validate environment
    validate_environment
    
    # Setup directories
    setup_directories
    
    # Start GPU swarms
    echo_magenta "╔════════════════════════════════════════════════════════════════╗"
    echo_magenta "║        LAUNCHING GPU SWARMS                                     ║"
    echo_magenta "╚════════════════════════════════════════════════════════════════╝"
    echo_cyan "Each GPU will manage $INSTANCES_PER_GPU swarm instances independently"
    echo ""
    
    for gpu_id in $(seq 0 $((NUM_GPUS - 1))); do
        start_gpu_swarm $gpu_id
        sleep 8  # Stagger GPU swarm starts to avoid resource contention
    done
    
    echo ""
    echo_green "╔════════════════════════════════════════════════════════════════╗"
    echo_green "║        ALL GPU SWARMS LAUNCHED                                  ║"
    echo_green "╚════════════════════════════════════════════════════════════════╝"
    echo_cyan "Total active swarms: $NUM_GPUS"
    echo_cyan "Total swarm instances: $((NUM_GPUS * INSTANCES_PER_GPU))"
    echo ""
    
    sleep 10
    
    # Start monitoring
    monitor_loop
}

main
