#!/usr/bin/env bash

set -euo pipefail

# ==============================================================================
# Multi-Instance RL Swarm Runner - AUTOMATED (No Web Login Required)
# ==============================================================================
# This version automatically reuses existing credentials and skips the web UI
# Perfect for headless/SSH environments where port forwarding is problematic
# ==============================================================================

ROOT=$PWD

# GenRL Swarm version to use
GENRL_TAG="0.1.9"

# Configuration
NUM_INSTANCES=${NUM_INSTANCES:-3}
GPU_MEMORY_PER_INSTANCE=${GPU_MEMORY_PER_INSTANCE:-8000}
MONITOR_INTERVAL=${MONITOR_INTERVAL:-60}
AUTO_RESTART=${AUTO_RESTART:-"yes"}
LOG_BASE_DIR="$ROOT/user/logs/multi_swarm"

# Pre-configured credentials (extracted from existing userData.json)
EXISTING_CREDENTIALS="/root/userData.json"
ORG_ID="b7b8ac33-4087-497b-a5f1-02ffe32fa29e"
WALLET_ADDRESS="0xF604Da031cE1354c8036C91766adaf669Fc7AAD0"

# Export for all instances
export CONNECT_TO_TESTNET=true
export ORG_ID
export SWARM_CONTRACT="0xFaD7C5e93f28257429569B854151A1B8DCD404c2"
export PRG_CONTRACT="0x51D4db531ae706a6eC732458825465058fA23a35"
export HUGGINGFACE_ACCESS_TOKEN="${HUGGINGFACE_ACCESS_TOKEN:-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}"
export PRG_GAME=true
export HF_HUB_DOWNLOAD_TIMEOUT=120

# ANSI colors
GREEN_TEXT="\033[32m"
BLUE_TEXT="\033[34m"
RED_TEXT="\033[31m"
YELLOW_TEXT="\033[33m"
CYAN_TEXT="\033[36m"
RESET_TEXT="\033[0m"

declare -a INSTANCE_PIDS=()
declare -a INSTANCE_NAMES=()
declare -a INSTANCE_LOGS=()

echo_green() { echo -e "$GREEN_TEXT$1$RESET_TEXT"; }
echo_blue() { echo -e "$BLUE_TEXT$1$RESET_TEXT"; }
echo_red() { echo -e "$RED_TEXT$1$RESET_TEXT"; }
echo_yellow() { echo -e "$YELLOW_TEXT$1$RESET_TEXT"; }
echo_cyan() { echo -e "$CYAN_TEXT$1$RESET_TEXT"; }

# ==============================================================================
# Installation
# ==============================================================================
install_dependencies() {
    echo_blue "=== Installing Dependencies ==="
    
    echo_green ">> Getting requirements..."
    python3 -m pip install --upgrade pip
    
    echo_green ">> Installing GenRL..."
    python3 -m pip install gensyn-genrl==${GENRL_TAG}
    python3 -m pip install reasoning-gym>=0.1.20 # for reasoning gym env
    python3 -m pip install hivemind@git+https://github.com/gensyn-ai/hivemind@639c964a8019de63135a2594663b5bec8e5356dd # We need the latest, 1.1.11 is broken
    
    echo_green ">> Ensuring jinja2 is up to date..."
    python3 -m pip install --upgrade 'jinja2>=3.1.0'
    
    echo_green "✓ Dependencies installed successfully"
    echo ""
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

    Multi-Instance Training - AUTOMATED MODE (No Web Login)
    Using existing credentials from $EXISTING_CREDENTIALS

EOF
echo -e "$RESET_TEXT"

# ==============================================================================
# Setup credentials
# ==============================================================================
setup_credentials() {
    echo_blue "=== Setting Up Credentials (Automated) ==="
    
    if [ -f "$EXISTING_CREDENTIALS" ]; then
        echo_green "✓ Found existing credentials: $EXISTING_CREDENTIALS"
        echo "  ORG_ID: $ORG_ID"
        echo "  Wallet: $WALLET_ADDRESS"
        
        # Copy to expected location for compatibility
        mkdir -p "$ROOT/modal-login/temp-data"
        cp "$EXISTING_CREDENTIALS" "$ROOT/modal-login/temp-data/userData.json"
        echo_green "✓ Credentials copied to modal-login/temp-data/"
    else
        echo_red "✗ No existing credentials found at $EXISTING_CREDENTIALS"
        echo_yellow "Please run the original script once to authenticate:"
        echo_yellow "  ./run_rl_swarm.sh"
        exit 1
    fi
    
    echo ""
}

# ==============================================================================
# Setup
# ==============================================================================
setup_directories() {
    echo_blue "Setting up directories for $NUM_INSTANCES instances..."
    
    mkdir -p "$LOG_BASE_DIR"
    
    # Setup base configs directory
    if [ ! -d "$ROOT/configs" ]; then
        mkdir "$ROOT/configs"
    fi
    
    # Copy or check base config
    if [ -f "$ROOT/configs/rg-swarm.yaml" ]; then
        if ! cmp -s "$ROOT/rgym_exp/config/rg-swarm.yaml" "$ROOT/configs/rg-swarm.yaml"; then
            echo_blue "  Base config differs from default, using existing config"
        fi
    else
        if [ -f "$ROOT/rgym_exp/config/rg-swarm.yaml" ]; then
            cp "$ROOT/rgym_exp/config/rg-swarm.yaml" "$ROOT/configs/rg-swarm.yaml"
            echo_green "  Created base config from default"
        fi
    fi
    
    for i in $(seq 1 $NUM_INSTANCES); do
        INSTANCE_DIR="$ROOT/user/instance_$i"
        mkdir -p "$INSTANCE_DIR"/{modal-login/temp-data,keys,configs,logs}
        
        # Copy credentials to each instance
        if [ -f "$EXISTING_CREDENTIALS" ]; then
            cp "$EXISTING_CREDENTIALS" "$INSTANCE_DIR/modal-login/temp-data/userData.json"
        fi
        
        # Copy base config to instance if it doesn't exist
        if [ ! -f "$INSTANCE_DIR/configs/rg-swarm.yaml" ]; then
            if [ -f "$ROOT/configs/rg-swarm.yaml" ]; then
                cp "$ROOT/configs/rg-swarm.yaml" "$INSTANCE_DIR/configs/rg-swarm.yaml"
            elif [ -f "$ROOT/rgym_exp/config/rg-swarm.yaml" ]; then
                cp "$ROOT/rgym_exp/config/rg-swarm.yaml" "$INSTANCE_DIR/configs/rg-swarm.yaml"
            fi
        fi
        
        INSTANCE_NAMES+=("swarm_instance_$i")
        INSTANCE_LOGS+=("$LOG_BASE_DIR/instance_${i}.log")
        
        echo_green "  Created instance_$i with credentials"
    done
}

check_gpu() {
    if command -v nvidia-smi &> /dev/null; then
        GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -n 1)
        GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1)
        echo_green "✓ GPU: $GPU_COUNT device(s) with ${GPU_MEMORY}MB"
        
        MAX_INSTANCES=$((GPU_MEMORY / GPU_MEMORY_PER_INSTANCE))
        if [ $NUM_INSTANCES -gt $MAX_INSTANCES ]; then
            echo_yellow "⚠ Requested $NUM_INSTANCES instances, recommended max: $MAX_INSTANCES"
        fi
    else
        echo_yellow "⚠ nvidia-smi not found"
    fi
}

# ==============================================================================
# Instance Management
# ==============================================================================
start_instance() {
    local instance_num=$1
    local instance_idx=$((instance_num - 1))
    local instance_name="${INSTANCE_NAMES[$instance_idx]}"
    local instance_log="${INSTANCE_LOGS[$instance_idx]}"
    local instance_dir="$ROOT/user/instance_$instance_num"
    
    echo_cyan "▶ Starting instance $instance_num..."
    
    # Create wrapper script
    local wrapper_script="$instance_dir/run_instance.sh"
    
    cat > "$wrapper_script" << WRAPPER_EOF
#!/usr/bin/env bash
set -euo pipefail

export INSTANCE_NUM=$instance_num
export IDENTITY_PATH="$instance_dir/keys/swarm_${instance_num}.pem"
export CONNECT_TO_TESTNET=true
export ORG_ID="$ORG_ID"
export HF_HUB_DOWNLOAD_TIMEOUT=120
export SWARM_CONTRACT="$SWARM_CONTRACT"
export PRG_CONTRACT="$PRG_CONTRACT"
export HUGGINGFACE_ACCESS_TOKEN="$HUGGINGFACE_ACCESS_TOKEN"
export PRG_GAME=true
export ROOT="$ROOT"
export CUDA_VISIBLE_DEVICES=0

echo "=== Instance $instance_num Starting (Automated) ===" >> "$instance_log"
echo "Timestamp: \$(date)" >> "$instance_log"
echo "PID: \$\$" >> "$instance_log"
echo "ORG_ID: $ORG_ID" >> "$instance_log"
echo "Identity: \$IDENTITY_PATH" >> "$instance_log"
echo "" >> "$instance_log"

cd "$ROOT"

# Continuous restart loop
RUN_COUNT=0
while true; do
    RUN_COUNT=\$((RUN_COUNT + 1))
    echo "" >> "$instance_log"
    echo "=== Starting swarm launcher (Run #\$RUN_COUNT) at \$(date) ===" >> "$instance_log"
    
    python -m rgym_exp.runner.swarm_launcher \\
        --config-path "$instance_dir/configs" \\
        --config-name "rg-swarm.yaml" \\
        >> "$instance_log" 2>&1
    
    EXIT_CODE=\$?
    
    if [ \$EXIT_CODE -eq 0 ]; then
        echo "=== Swarm launcher exited normally. Restarting in 5 seconds... ===" >> "$instance_log"
        sleep 5
    else
        echo "=== Swarm launcher exited with error code \$EXIT_CODE. Restarting in 10 seconds... ===" >> "$instance_log"
        sleep 10
    fi
done
WRAPPER_EOF
    
    chmod +x "$wrapper_script"
    
    # Start in background
    nohup bash "$wrapper_script" &> /dev/null &
    local pid=$!
    
    INSTANCE_PIDS[$instance_idx]=$pid
    
    sleep 2
    
    if kill -0 $pid 2>/dev/null; then
        echo_green "  ✓ Instance $instance_num started (PID: $pid)"
        echo_blue "    Log: $instance_log"
    else
        echo_red "  ✗ Instance $instance_num failed to start"
    fi
}

stop_instance() {
    local instance_num=$1
    local instance_idx=$((instance_num - 1))
    local pid="${INSTANCE_PIDS[$instance_idx]}"
    
    if [ -n "$pid" ] && kill -0 $pid 2>/dev/null; then
        echo_yellow "◼ Stopping instance $instance_num (PID: $pid)..."
        kill -TERM $pid 2>/dev/null || true
        
        for i in {1..10}; do
            if ! kill -0 $pid 2>/dev/null; then
                echo_green "  ✓ Instance $instance_num stopped"
                return 0
            fi
            sleep 1
        done
        
        kill -KILL $pid 2>/dev/null || true
        echo_yellow "  ⚠ Instance $instance_num force-killed"
    fi
}

# ==============================================================================
# Monitoring
# ==============================================================================
monitor_gpu_usage() {
    if command -v nvidia-smi &> /dev/null; then
        nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits | head -n 1
    else
        echo "N/A,N/A,N/A"
    fi
}

check_instance_health() {
    local instance_num=$1
    local instance_idx=$((instance_num - 1))
    local pid="${INSTANCE_PIDS[$instance_idx]}"
    
    if [ -z "$pid" ] || ! kill -0 $pid 2>/dev/null; then
        return 1
    fi
    return 0
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
            
            if check_instance_health $i; then
                echo_green "  ✓ Instance $i: HEALTHY (PID: $pid)"
                if [ -f "$instance_log" ]; then
                    local last_line=$(tail -n 1 "$instance_log" 2>/dev/null | cut -c 1-80 || echo "")
                    [ -n "$last_line" ] && echo "    Last: $last_line"
                fi
            else
                echo_red "  ✗ Instance $i: NOT RUNNING"
                if [ "$AUTO_RESTART" = "yes" ]; then
                    echo_yellow "    Attempting restart..."
                    start_instance $i
                fi
            fi
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
    echo_blue "Logs: $LOG_BASE_DIR"
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# ==============================================================================
# Main
# ==============================================================================
main() {
    echo_blue "=== Multi-Instance Configuration (Automated) ==="
    echo "Instances: $NUM_INSTANCES"
    echo "GPU memory per instance: ${GPU_MEMORY_PER_INSTANCE}MB"
    echo "Monitor interval: ${MONITOR_INTERVAL}s"
    echo "Auto-restart: $AUTO_RESTART"
    echo "ORG_ID: $ORG_ID"
    echo "Log directory: $LOG_BASE_DIR"
    echo ""
    
    # Install dependencies
    install_dependencies
    
    # Setup
    setup_credentials
    check_gpu
    echo ""
    
    setup_directories
    echo ""
    
    # Start instances
    echo_blue "=== Starting $NUM_INSTANCES Instances ==="
    for i in $(seq 1 $NUM_INSTANCES); do
        start_instance $i
        sleep 5  # Stagger starts
    done
    echo ""
    
    sleep 5
    
    # Monitor
    monitor_loop
}

main

