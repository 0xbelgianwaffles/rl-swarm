#!/usr/bin/env bash

set -euo pipefail

# ==============================================================================
# Multi-Instance RL Swarm Runner - DOCKER VERSION
# ==============================================================================
# This version uses Docker Compose to run multiple GPU-enabled containers
# Each container runs one training instance with full GPU access
# ==============================================================================

ROOT=$PWD

# Configuration
NUM_INSTANCES=${NUM_INSTANCES:-3}
BASE_PORT=${BASE_PORT:-3000}
GPU_MEMORY_FRACTION=${GPU_MEMORY_FRACTION:-0.33}  # Each instance gets ~33% of GPU
MONITOR_INTERVAL=${MONITOR_INTERVAL:-60}
AUTO_RESTART=${AUTO_RESTART:-"yes"}
LOG_BASE_DIR="$ROOT/user/logs/multi_swarm"

# Docker image to use (from original setup)
DOCKER_IMAGE="rl-swarm-swarm-gpu"

# Colors
GREEN_TEXT="\033[32m"
BLUE_TEXT="\033[34m"
RED_TEXT="\033[31m"
YELLOW_TEXT="\033[33m"
CYAN_TEXT="\033[36m"
RESET_TEXT="\033[0m"

# Arrays to track containers
declare -a CONTAINER_NAMES=()
declare -a CONTAINER_IDS=()
declare -a INSTANCE_PORTS=()

echo_green() { echo -e "$GREEN_TEXT$1$RESET_TEXT"; }
echo_blue() { echo -e "$BLUE_TEXT$1$RESET_TEXT"; }
echo_red() { echo -e "$RED_TEXT$1$RESET_TEXT"; }
echo_yellow() { echo -e "$YELLOW_TEXT$1$RESET_TEXT"; }
echo_cyan() { echo -e "$CYAN_TEXT$1$RESET_TEXT"; }

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

    Multi-Instance Parallel Training Manager (DOCKER MODE)
    From Gensyn

EOF
echo -e "$RESET_TEXT"

# ==============================================================================
# Pre-flight checks
# ==============================================================================
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo_red "✗ Docker not found"
        return 1
    fi
    
    if ! docker info &> /dev/null; then
        echo_red "✗ Docker daemon not running"
        return 1
    fi
    
    echo_green "✓ Docker available"
    
    # Check if NVIDIA Docker works
    if docker run --rm --gpus all nvidia/cuda:12.6.3-cudnn-devel-ubuntu24.04 nvidia-smi &> /dev/null; then
        echo_green "✓ NVIDIA Docker runtime working"
    else
        echo_yellow "⚠ NVIDIA Docker might have issues, but continuing..."
    fi
    
    # Check if image exists
    if docker images | grep -q "$DOCKER_IMAGE"; then
        echo_green "✓ Docker image '$DOCKER_IMAGE' found"
    else
        echo_yellow "⚠ Docker image '$DOCKER_IMAGE' not found"
        echo_blue "  Building image (this may take a while)..."
        docker compose build swarm-gpu || {
            echo_red "✗ Failed to build image"
            return 1
        }
    fi
    
    return 0
}

check_gpu() {
    if command -v nvidia-smi &> /dev/null; then
        GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -n 1)
        GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1)
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n 1)
        echo_green "✓ GPU: $GPU_NAME (${GPU_MEMORY}MB)"
        
        # Calculate max instances
        local mem_per_instance=$((GPU_MEMORY / NUM_INSTANCES))
        echo_blue "  Each instance will have ~${mem_per_instance}MB available"
        
        return 0
    else
        echo_red "✗ nvidia-smi not found"
        return 1
    fi
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
        
        local container_name="rl_swarm_instance_$i"
        local port=$((BASE_PORT + i - 1))
        
        CONTAINER_NAMES+=("$container_name")
        INSTANCE_PORTS+=($port)
        
        echo_green "  Created instance_$i → container: $container_name, port: $port"
    done
}

# ==============================================================================
# Container Management
# ==============================================================================
start_container() {
    local instance_num=$1
    local instance_idx=$((instance_num - 1))
    local container_name="${CONTAINER_NAMES[$instance_idx]}"
    local instance_port="${INSTANCE_PORTS[$instance_idx]}"
    local instance_dir="$ROOT/user/instance_$instance_num"
    local instance_log="$LOG_BASE_DIR/instance_${instance_num}.log"
    
    # Check if container already exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo_yellow "  Container $container_name already exists, removing..."
        docker rm -f "$container_name" &> /dev/null || true
    fi
    
    echo_cyan "▶ Starting container $container_name on port $instance_port..."
    
    # Start Docker container with GPU access
    # Use CUDA_VISIBLE_DEVICES and memory fraction to limit GPU usage per container
    local container_id=$(docker run -d \
        --name "$container_name" \
        --gpus all \
        -e CUDA_VISIBLE_DEVICES=0 \
        -e PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb:512" \
        -e INSTANCE_NUM=$instance_num \
        -e GENSYN_RESET_CONFIG="" \
        -e HF_TOKEN="${HF_TOKEN:-}" \
        -e HUGGINGFACE_ACCESS_TOKEN="${HUGGINGFACE_ACCESS_TOKEN:-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}" \
        -e SWARM_CONTRACT="0xFaD7C5e93f28257429569B854151A1B8DCD404c2" \
        -e PRG_CONTRACT="0x51D4db531ae706a6eC732458825465058fA23a35" \
        -e PRG_GAME=true \
        -p "${instance_port}:3000" \
        -v "$instance_dir/modal-login:/home/gensyn/rl_swarm/modal-login/temp-data" \
        -v "$instance_dir/keys:/home/gensyn/rl_swarm/keys" \
        -v "$instance_dir/configs:/home/gensyn/rl_swarm/configs" \
        -v "$instance_dir/logs:/home/gensyn/rl_swarm/logs" \
        --shm-size=2g \
        "$DOCKER_IMAGE" \
        /bin/bash -c "cd /home/gensyn/rl_swarm && ./run_rl_swarm.sh" \
        2>&1 | tee -a "$instance_log")
    
    if [ -n "$container_id" ]; then
        CONTAINER_IDS[$instance_idx]=$container_id
        echo_green "  ✓ Container started: $container_name (ID: ${container_id:0:12})"
        echo_blue "    Port: $instance_port | Log: $instance_log"
        
        # Follow logs in background
        docker logs -f "$container_name" >> "$instance_log" 2>&1 &
    else
        echo_red "  ✗ Failed to start container $container_name"
        return 1
    fi
}

stop_container() {
    local instance_num=$1
    local instance_idx=$((instance_num - 1))
    local container_name="${CONTAINER_NAMES[$instance_idx]}"
    
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo_yellow "◼ Stopping container $container_name..."
        docker stop "$container_name" &> /dev/null
        docker rm "$container_name" &> /dev/null
        echo_green "  ✓ Container stopped and removed"
    else
        echo_yellow "  Container $container_name not running"
    fi
}

# ==============================================================================
# Monitoring
# ==============================================================================
check_container_health() {
    local container_name=$1
    
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        local status=$(docker inspect --format='{{.State.Status}}' "$container_name")
        if [ "$status" = "running" ]; then
            return 0  # Healthy
        else
            return 2  # Unhealthy
        fi
    else
        return 1  # Not running
    fi
}

monitor_gpu_usage() {
    if command -v nvidia-smi &> /dev/null; then
        local gpu_usage=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits | head -n 1)
        echo "$gpu_usage"
    else
        echo "N/A,N/A,N/A,N/A"
    fi
}

monitor_loop() {
    echo_blue "Starting monitoring loop (interval: ${MONITOR_INTERVAL}s)..."
    echo_blue "Press Ctrl+C to stop all containers and exit"
    echo ""
    
    local iteration=0
    
    while true; do
        iteration=$((iteration + 1))
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        
        echo_cyan "=== Monitor Check #$iteration at $timestamp ==="
        
        # GPU stats
        local gpu_stats=$(monitor_gpu_usage)
        IFS=',' read -r gpu_util gpu_mem_used gpu_mem_total gpu_temp <<< "$gpu_stats"
        echo "GPU: ${gpu_util}% utilization | Memory: ${gpu_mem_used}MB / ${gpu_mem_total}MB | Temp: ${gpu_temp}°C"
        
        # Check each container
        for i in $(seq 1 $NUM_INSTANCES); do
            local instance_idx=$((i - 1))
            local container_name="${CONTAINER_NAMES[$instance_idx]}"
            local container_id="${CONTAINER_IDS[$instance_idx]:-}"
            
            check_container_health "$container_name"
            local health_status=$?
            
            case $health_status in
                0)
                    echo_green "  ✓ Instance $i ($container_name): RUNNING"
                    
                    # Show container stats
                    if [ -n "$container_id" ]; then
                        local stats=$(docker stats --no-stream --format "{{.CPUPerc}} {{.MemPerc}}" "$container_name" 2>/dev/null || echo "N/A N/A")
                        echo "    CPU: $(echo $stats | cut -d' ' -f1) | Memory: $(echo $stats | cut -d' ' -f2)"
                    fi
                    ;;
                1)
                    echo_red "  ✗ Instance $i ($container_name): NOT RUNNING"
                    if [ "$AUTO_RESTART" = "yes" ]; then
                        echo_yellow "    Attempting restart..."
                        start_container $i
                    fi
                    ;;
                2)
                    echo_yellow "  ⚠ Instance $i ($container_name): UNHEALTHY"
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
        stop_container $i
    done
    
    echo_green "=== All containers stopped ==="
    echo_blue "Logs available at: $LOG_BASE_DIR"
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# ==============================================================================
# Main Execution
# ==============================================================================
main() {
    echo_blue "=== Multi-Instance RL Swarm Configuration (DOCKER MODE) ==="
    echo "Number of instances: $NUM_INSTANCES"
    echo "Base port: $BASE_PORT (will use $BASE_PORT-$((BASE_PORT + NUM_INSTANCES - 1)))"
    echo "GPU memory fraction per instance: $GPU_MEMORY_FRACTION"
    echo "Monitor interval: ${MONITOR_INTERVAL}s"
    echo "Auto-restart: $AUTO_RESTART"
    echo "Log directory: $LOG_BASE_DIR"
    echo ""
    
    # Pre-flight checks
    echo_blue "=== Pre-flight Checks ==="
    if ! check_docker; then
        echo_red "Docker check failed. Exiting."
        exit 1
    fi
    
    if ! check_gpu; then
        echo_yellow "GPU check had warnings, but continuing..."
    fi
    
    echo ""
    
    # Setup
    setup_directories
    echo ""
    
    # Start all containers
    echo_blue "=== Starting $NUM_INSTANCES Docker Containers ==="
    for i in $(seq 1 $NUM_INSTANCES); do
        start_container $i
        sleep 5  # Stagger starts
    done
    echo ""
    
    sleep 5
    
    # Enter monitoring loop
    monitor_loop
}

# Run main
main

