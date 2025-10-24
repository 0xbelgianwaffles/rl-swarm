#!/usr/bin/env bash

set -euo pipefail

# ==============================================================================
# Headless RL Swarm Runner - NO WEB LOGIN REQUIRED
# ==============================================================================
# This is a modified version of run_rl_swarm.sh that skips the web UI
# It expects userData.json to already exist
# ==============================================================================

# General arguments
ROOT=$PWD

# GenRL Swarm version to use
GENRL_TAG="0.1.9"

export IDENTITY_PATH
export GENSYN_RESET_CONFIG
export CONNECT_TO_TESTNET=false  # Skip testnet login!
export ORG_ID
export HF_HUB_DOWNLOAD_TIMEOUT=120
export SWARM_CONTRACT="0xFaD7C5e93f28257429569B854151A1B8DCD404c2"
export PRG_CONTRACT="0x51D4db531ae706a6eC732458825465058fA23a35"
export HUGGINGFACE_ACCESS_TOKEN="${HUGGINGFACE_ACCESS_TOKEN:-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}"
export PRG_GAME=true

# Path to an RSA private key
DEFAULT_IDENTITY_PATH="$ROOT"/swarm.pem
IDENTITY_PATH=${IDENTITY_PATH:-$DEFAULT_IDENTITY_PATH}

DOCKER=${DOCKER:-""}
GENSYN_RESET_CONFIG=${GENSYN_RESET_CONFIG:-""}

# Bit of a workaround for the non-root docker container
if [ -n "$DOCKER" ]; then
    volumes=(
        /home/gensyn/rl_swarm/modal-login/temp-data
        /home/gensyn/rl_swarm/keys
        /home/gensyn/rl_swarm/configs
        /home/gensyn/rl_swarm/logs
    )

    for volume in ${volumes[@]}; do
        sudo chown -R 1001:1001 $volume 2>/dev/null || true
    done
fi

# Set if successfully parsed from modal-login/temp-data/userData.json
ORG_ID=${ORG_ID:-""}

GREEN_TEXT="\033[32m"
BLUE_TEXT="\033[34m"
RED_TEXT="\033[31m"
RESET_TEXT="\033[0m"

echo_green() {
    echo -e "$GREEN_TEXT$1$RESET_TEXT"
}

echo_blue() {
    echo -e "$BLUE_TEXT$1$RESET_TEXT"
}

echo_red() {
    echo -e "$RED_TEXT$1$RESET_TEXT"
}

ROOT_DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"

# Function to clean up upon exit
cleanup() {
    echo_green ">> Shutting down trainer..."
    # Don't remove credentials - we want to keep them!
    kill -- -$$ || true
    exit 0
}

errnotify() {
    echo_red ">> An error was detected while running rl-swarm. See $ROOT/logs for full logs."
}

trap cleanup EXIT
trap errnotify ERR

echo -e "\033[38;5;224m"
cat << "EOF"
    ██████  ██            ███████ ██     ██  █████  ██████  ███    ███
    ██   ██ ██            ██      ██     ██ ██   ██ ██   ██ ████  ████
    ██████  ██      █████ ███████ ██  █  ██ ███████ ██████  ██ ████ ██
    ██   ██ ██                 ██ ██ ███ ██ ██   ██ ██   ██ ██  ██  ██
    ██   ██ ███████       ███████  ███ ███  ██   ██ ██   ██ ██      ██

    From Gensyn - HEADLESS MODE (No Web Login)

EOF

# Create logs directory
mkdir -p "$ROOT/logs"

# Check for existing credentials
if [ -f "modal-login/temp-data/userData.json" ]; then
    echo_green ">> Found existing credentials, skipping web login"
    ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)
    echo_green ">> Your ORG_ID is: $ORG_ID"
else
    echo_red ">> ERROR: No credentials found!"
    echo_red ">> Expected file: modal-login/temp-data/userData.json"
    echo_blue ">> Please run the original script once to authenticate, or copy your credentials:"
    echo_blue ">>   cp /root/userData.json $ROOT/modal-login/temp-data/userData.json"
    exit 1
fi

echo_green ">> Getting requirements..."
pip install --upgrade pip

echo_green ">> Installing GenRL..."
pip install gensyn-genrl==${GENRL_TAG}
pip install reasoning-gym>=0.1.20
pip install hivemind@git+https://github.com/gensyn-ai/hivemind@639c964a8019de63135a2594663b5bec8e5356dd

# Handle config
if [ ! -d "$ROOT/configs" ]; then
    mkdir "$ROOT/configs"
fi  
if [ -f "$ROOT/configs/rg-swarm.yaml" ]; then
    if ! cmp -s "$ROOT/rgym_exp/config/rg-swarm.yaml" "$ROOT/configs/rg-swarm.yaml"; then
        if [ -z "$GENSYN_RESET_CONFIG" ]; then
            echo_green ">> Found differences in rg-swarm.yaml. If you would like to reset to the default, set GENSYN_RESET_CONFIG to a non-empty value."
        else
            echo_green ">> Found differences in rg-swarm.yaml. Backing up existing config."
            mv "$ROOT/configs/rg-swarm.yaml" "$ROOT/configs/rg-swarm.yaml.bak"
            cp "$ROOT/rgym_exp/config/rg-swarm.yaml" "$ROOT/configs/rg-swarm.yaml"
        fi
    fi
else
    cp "$ROOT/rgym_exp/config/rg-swarm.yaml" "$ROOT/configs/rg-swarm.yaml"
fi

if [ -n "$DOCKER" ]; then
    sudo chmod -R 0777 /home/gensyn/rl_swarm/configs 2>/dev/null || true
fi

echo_green ">> Done!"

# Skip the interactive prompts for headless mode
echo_green ">> Using HuggingFace token: ${HUGGINGFACE_ACCESS_TOKEN:0:10}..."
echo_green ">> Using default model from config"
echo_green ">> Playing PRG game: $PRG_GAME"

echo_green ">> Good luck in the swarm!"
echo_blue ">> And remember to star the repo on GitHub! --> https://github.com/gensyn-ai/rl-swarm"

python -m rgym_exp.runner.swarm_launcher \
    --config-path "$ROOT/rgym_exp/config" \
    --config-name "rg-swarm.yaml" 

wait

echo_green ">> Done!"