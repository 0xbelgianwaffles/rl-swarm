#!/usr/bin/env bash

# ==============================================================================
# Multi-Instance Setup Validator
# ==============================================================================
# Run this before starting multi-instance training to verify your setup
# ==============================================================================

set -euo pipefail

ROOT=$PWD

# Colors
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[34m"
RESET="\033[0m"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

check_pass() {
    echo -e "${GREEN}✓${RESET} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

check_fail() {
    echo -e "${RED}✗${RESET} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

check_warn() {
    echo -e "${YELLOW}⚠${RESET} $1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     Multi-Instance RL Swarm Setup Validator                  ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo ""

# ==============================================================================
# System Checks
# ==============================================================================
echo -e "${BLUE}=== System Requirements ===${RESET}"

# Check OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    check_pass "Operating System: Linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    check_warn "Operating System: macOS (limited GPU support)"
else
    check_fail "Operating System: Unknown ($OSTYPE)"
fi

# Check bash version
BASH_VERSION_NUM=$(bash --version | head -n1 | grep -oP '\d+\.\d+' | head -n1)
if (( $(echo "$BASH_VERSION_NUM >= 4.0" | bc -l) )); then
    check_pass "Bash version: $BASH_VERSION_NUM"
else
    check_fail "Bash version: $BASH_VERSION_NUM (need >= 4.0)"
fi

# Check Python
if command -v python &> /dev/null; then
    PYTHON_VERSION=$(python --version 2>&1 | grep -oP '\d+\.\d+\.\d+')
    check_pass "Python found: $PYTHON_VERSION"
    
    # Check Python version
    PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
    PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)
    if [ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -ge 8 ]; then
        check_pass "Python version compatible (>= 3.8)"
    else
        check_fail "Python version $PYTHON_VERSION (need >= 3.8)"
    fi
else
    check_fail "Python not found"
fi

# Check pip
if command -v pip &> /dev/null; then
    check_pass "pip found: $(pip --version | cut -d' ' -f2)"
else
    check_fail "pip not found"
fi

echo ""

# ==============================================================================
# GPU Checks
# ==============================================================================
echo -e "${BLUE}=== GPU Configuration ===${RESET}"

if command -v nvidia-smi &> /dev/null; then
    check_pass "nvidia-smi found"
    
    # Get GPU info
    GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -n 1)
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n 1)
    GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1)
    GPU_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1)
    
    check_pass "GPU Count: $GPU_COUNT"
    check_pass "GPU Model: $GPU_NAME"
    check_pass "GPU Memory: ${GPU_MEMORY}MB"
    check_pass "Driver Version: $GPU_DRIVER"
    
    # Memory recommendations
    if [ "$GPU_MEMORY" -ge 24000 ]; then
        echo -e "  ${GREEN}→ Recommended: 3 instances (24GB GPU)${RESET}"
    elif [ "$GPU_MEMORY" -ge 16000 ]; then
        echo -e "  ${GREEN}→ Recommended: 2 instances (16GB GPU)${RESET}"
    elif [ "$GPU_MEMORY" -ge 12000 ]; then
        echo -e "  ${YELLOW}→ Recommended: 2 instances (12GB GPU, use smaller models)${RESET}"
    else
        echo -e "  ${YELLOW}→ Recommended: 1 instance (<12GB GPU)${RESET}"
    fi
    
    # Check CUDA
    if command -v nvcc &> /dev/null; then
        CUDA_VERSION=$(nvcc --version | grep "release" | grep -oP '\d+\.\d+')
        check_pass "CUDA found: $CUDA_VERSION"
    else
        check_warn "nvcc not found (CUDA may still work via conda/pip)"
    fi
    
else
    check_fail "nvidia-smi not found - No GPU detected"
    echo -e "  ${RED}→ GPU is required for training${RESET}"
fi

echo ""

# ==============================================================================
# Dependencies
# ==============================================================================
echo -e "${BLUE}=== Python Dependencies ===${RESET}"

check_python_package() {
    local package=$1
    local import_name=${2:-$1}
    if python -c "import $import_name" 2>/dev/null; then
        local version=$(python -c "import $import_name; print(getattr($import_name, '__version__', 'unknown'))" 2>/dev/null)
        check_pass "$package installed ($version)"
    else
        check_fail "$package not installed"
    fi
}

check_python_package "torch" "torch"
check_python_package "transformers" "transformers"
check_python_package "gensyn-genrl" "genrl"
check_python_package "reasoning-gym" "reasoning_gym"
check_python_package "hivemind" "hivemind"
check_python_package "wandb" "wandb"

echo ""

# ==============================================================================
# File Structure
# ==============================================================================
echo -e "${BLUE}=== File Structure ===${RESET}"

check_file() {
    local file=$1
    if [ -f "$ROOT/$file" ]; then
        check_pass "$file exists"
    else
        check_fail "$file not found"
    fi
}

check_dir() {
    local dir=$1
    if [ -d "$ROOT/$dir" ]; then
        check_pass "$dir/ exists"
    else
        check_fail "$dir/ not found"
    fi
}

check_file "run_rl_swarm.sh"
check_file "run_multi_swarm.sh"
check_file "monitor_swarm_status.sh"
check_file "docker-compose.yaml"
check_dir "rgym_exp"
check_dir "rgym_exp/config"
check_file "rgym_exp/config/rg-swarm.yaml"
check_file "rgym_exp/runner/swarm_launcher.py"
check_dir "modal-login"
check_dir "user"

echo ""

# ==============================================================================
# Docker (if applicable)
# ==============================================================================
echo -e "${BLUE}=== Docker (Optional) ===${RESET}"

if command -v docker &> /dev/null; then
    check_pass "Docker found: $(docker --version | cut -d' ' -f3 | tr -d ',')"
    
    # Check if Docker daemon is running
    if docker info &> /dev/null; then
        check_pass "Docker daemon is running"
        
        # Check docker-compose
        if command -v docker-compose &> /dev/null; then
            check_pass "docker-compose found: $(docker-compose --version | grep -oP '\d+\.\d+\.\d+' | head -n1)"
        elif docker compose version &> /dev/null; then
            check_pass "docker compose (plugin) found"
        else
            check_warn "docker-compose not found (optional)"
        fi
        
        # Check for NVIDIA Docker
        if docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi &> /dev/null; then
            check_pass "NVIDIA Docker runtime working"
        else
            check_warn "NVIDIA Docker runtime not configured (needed for GPU in Docker)"
        fi
    else
        check_warn "Docker daemon not running"
    fi
else
    check_warn "Docker not found (can run without Docker)"
fi

echo ""

# ==============================================================================
# Network Ports
# ==============================================================================
echo -e "${BLUE}=== Network Ports ===${RESET}"

check_port() {
    local port=$1
    if lsof -i:$port &> /dev/null; then
        check_warn "Port $port is in use"
        local pid=$(lsof -ti:$port | head -n1)
        local process=$(ps -p $pid -o comm= 2>/dev/null || echo "unknown")
        echo -e "  ${YELLOW}→ Used by PID $pid ($process)${RESET}"
    else
        check_pass "Port $port is available"
    fi
}

check_port 3000
check_port 3001
check_port 3002

echo ""

# ==============================================================================
# Disk Space
# ==============================================================================
echo -e "${BLUE}=== Disk Space ===${RESET}"

AVAILABLE_SPACE=$(df -BG "$ROOT" | awk 'NR==2 {print $4}' | sed 's/G//')
USED_SPACE=$(df -BG "$ROOT" | awk 'NR==2 {print $3}' | sed 's/G//')

if [ "$AVAILABLE_SPACE" -ge 50 ]; then
    check_pass "Available disk space: ${AVAILABLE_SPACE}GB"
elif [ "$AVAILABLE_SPACE" -ge 20 ]; then
    check_warn "Available disk space: ${AVAILABLE_SPACE}GB (20GB+ recommended)"
else
    check_fail "Available disk space: ${AVAILABLE_SPACE}GB (insufficient, need 20GB+)"
fi

echo ""

# ==============================================================================
# Permissions
# ==============================================================================
echo -e "${BLUE}=== Permissions ===${RESET}"

if [ -x "$ROOT/run_multi_swarm.sh" ]; then
    check_pass "run_multi_swarm.sh is executable"
else
    check_fail "run_multi_swarm.sh is not executable"
    echo -e "  ${YELLOW}→ Run: chmod +x run_multi_swarm.sh${RESET}"
fi

if [ -x "$ROOT/monitor_swarm_status.sh" ]; then
    check_pass "monitor_swarm_status.sh is executable"
else
    check_fail "monitor_swarm_status.sh is not executable"
    echo -e "  ${YELLOW}→ Run: chmod +x monitor_swarm_status.sh${RESET}"
fi

if [ -w "$ROOT/user" ]; then
    check_pass "user/ directory is writable"
else
    check_fail "user/ directory is not writable"
fi

echo ""

# ==============================================================================
# Configuration
# ==============================================================================
echo -e "${BLUE}=== Configuration ===${RESET}"

if [ -f "$ROOT/rgym_exp/config/rg-swarm.yaml" ]; then
    # Check for required environment variables in config
    if grep -q "SWARM_CONTRACT" "$ROOT/rgym_exp/config/rg-swarm.yaml"; then
        check_pass "Config references SWARM_CONTRACT"
    else
        check_warn "SWARM_CONTRACT not found in config"
    fi
    
    if grep -q "ORG_ID" "$ROOT/rgym_exp/config/rg-swarm.yaml"; then
        check_pass "Config references ORG_ID"
    else
        check_warn "ORG_ID not found in config"
    fi
fi

echo ""

# ==============================================================================
# Summary
# ==============================================================================
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BLUE}║                    VALIDATION SUMMARY                         ║${RESET}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${GREEN}Passed:${RESET}  $PASS_COUNT"
echo -e "${YELLOW}Warnings:${RESET} $WARN_COUNT"
echo -e "${RED}Failed:${RESET}  $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ All critical checks passed!${RESET}"
    echo ""
    echo "You can now run:"
    echo -e "  ${BLUE}./run_multi_swarm.sh${RESET}           # Start multi-instance training"
    echo -e "  ${BLUE}./monitor_swarm_status.sh --watch${RESET}  # Monitor in separate terminal"
    echo ""
    exit 0
elif [ $FAIL_COUNT -le 3 ]; then
    echo -e "${YELLOW}⚠ Some checks failed, but you may still be able to proceed${RESET}"
    echo "Review the failures above and fix them if possible."
    echo ""
    exit 1
else
    echo -e "${RED}✗ Multiple critical checks failed${RESET}"
    echo "Please fix the issues above before proceeding."
    echo ""
    exit 1
fi

