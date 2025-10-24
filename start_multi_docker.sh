#!/usr/bin/env bash

set -euo pipefail

# ==============================================================================
# Multi-Instance Docker-Based RL Swarm Launcher
# ==============================================================================
# This script sets up and runs multiple Docker containers for parallel training
# Bypasses the web login by pre-seeding credentials
# ==============================================================================

ROOT=$PWD
NUM_INSTANCES=${NUM_INSTANCES:-3}
EXISTING_CREDENTIALS="/root/userData.json"

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

# Banner
echo -e "\033[38;5;224m"
cat << "EOF"
    ███    ███ ██    ██ ██      ████████ ██      ██████   ██████   ██████ ██   ██ ███████ ██████  
    ████  ████ ██    ██ ██         ██    ██      ██   ██ ██    ██ ██      ██  ██  ██      ██   ██ 
    ██ ████ ██ ██    ██ ██         ██    ██ ███████   ██ ██    ██ ██      █████   █████   ██████  
    ██  ██  ██ ██    ██ ██         ██    ██      ██   ██ ██    ██ ██      ██  ██  ██      ██   ██ 
    ██      ██  ██████  ███████    ██    ██      ██████   ██████   ██████ ██   ██ ███████ ██   ██ 

    Multi-Instance Training via Docker
    No Web Login Required - Automated Setup

EOF
echo -e "$RESET"

echo_blue "=== Configuration ==="
echo "Instances: $NUM_INSTANCES"
echo "Using Docker Compose: docker-compose-multi.yaml"
echo ""

# Check for credentials
if [ ! -f "$EXISTING_CREDENTIALS" ]; then
    echo_red "✗ No credentials found at $EXISTING_CREDENTIALS"
    echo_yellow "Please run the original script once to authenticate:"
    echo_yellow "  docker compose run --rm --build -Pit swarm-gpu"
    exit 1
fi

echo_green "✓ Found credentials: $EXISTING_CREDENTIALS"
echo ""

# Setup instance directories
echo_blue "=== Setting Up Instance Directories ==="
for i in $(seq 1 $NUM_INSTANCES); do
    INSTANCE_DIR="$ROOT/user/instance_$i"
    mkdir -p "$INSTANCE_DIR"/{modal-login,keys,configs,logs}
    
    # Copy credentials to bypass web login
    if [ -f "$EXISTING_CREDENTIALS" ]; then
        cp "$EXISTING_CREDENTIALS" "$INSTANCE_DIR/modal-login/userData.json"
        echo_green "  ✓ Instance $i: Credentials copied"
    fi
    
    # Copy base config
    if [ ! -f "$INSTANCE_DIR/configs/rg-swarm.yaml" ] && [ -f "$ROOT/rgym_exp/config/rg-swarm.yaml" ]; then
        cp "$ROOT/rgym_exp/config/rg-swarm.yaml" "$INSTANCE_DIR/configs/rg-swarm.yaml"
        echo_green "  ✓ Instance $i: Config copied"
    fi
    
    # Set permissions for Docker (gensyn user is UID 1001)
    chmod -R 777 "$INSTANCE_DIR" 2>/dev/null || true
done

echo ""
echo_blue "=== Building Docker Images (if needed) ==="
echo_yellow "This may take a few minutes on first run..."
echo ""

# Build the image once (shared by all instances)
docker compose -f docker-compose-multi.yaml build

echo ""
echo_green "✓ Build complete!"
echo ""

# Start containers
echo_blue "=== Starting $NUM_INSTANCES Docker Containers ==="
echo ""

# Generate service names based on NUM_INSTANCES
SERVICES=""
for i in $(seq 1 $NUM_INSTANCES); do
    SERVICES="$SERVICES swarm-instance-$i"
done

echo_cyan "Starting services: $SERVICES"
echo ""

# Start all containers in detached mode
docker compose -f docker-compose-multi.yaml up -d $SERVICES

echo ""
echo_green "✓ All instances started!"
echo ""

# Show status
echo_blue "=== Container Status ==="
docker compose -f docker-compose-multi.yaml ps
echo ""

# Show logs command
echo_cyan "╔════════════════════════════════════════════════════════════════════╗"
echo_cyan "║                    MULTI-INSTANCE RUNNING                          ║"
echo_cyan "╚════════════════════════════════════════════════════════════════════╝"
echo ""
echo_blue "Monitor logs:"
echo "  All instances:  docker compose -f docker-compose-multi.yaml logs -f"
echo "  Instance 1:     docker compose -f docker-compose-multi.yaml logs -f swarm-instance-1"
echo "  Instance 2:     docker compose -f docker-compose-multi.yaml logs -f swarm-instance-2"
echo "  Instance 3:     docker compose -f docker-compose-multi.yaml logs -f swarm-instance-3"
echo ""
echo_blue "Check GPU usage:"
echo "  watch -n 1 nvidia-smi"
echo ""
echo_blue "Stop all instances:"
echo "  docker compose -f docker-compose-multi.yaml down"
echo ""
echo_green "Happy training! 🚀"

