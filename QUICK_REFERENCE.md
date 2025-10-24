# RL-Swarm Multi-Instance Quick Reference

## 🚀 Quick Start Commands

```bash
# 1. Validate your setup first
./validate_multi_setup.sh

# 2. Start 3 parallel training instances
./run_multi_swarm.sh

# 3. Monitor in another terminal (watch mode)
./monitor_swarm_status.sh --watch

# 4. Check status anytime
./control_instance.sh status
```

## 📋 All Available Scripts

| Script | Purpose | Example Usage |
|--------|---------|---------------|
| `validate_multi_setup.sh` | Check system requirements before starting | `./validate_multi_setup.sh` |
| `run_multi_swarm.sh` | Start all instances with monitoring | `NUM_INSTANCES=3 ./run_multi_swarm.sh` |
| `monitor_swarm_status.sh` | Real-time dashboard of all instances | `./monitor_swarm_status.sh --watch` |
| `control_instance.sh` | Control individual instances | `./control_instance.sh start 1` |
| `run_rl_swarm.sh` | Original single-instance script (unchanged) | `./run_rl_swarm.sh` |

## 🎮 Control Commands

### Start/Stop All Instances
```bash
./control_instance.sh startall 3     # Start 3 instances
./control_instance.sh stopall        # Stop all instances
./control_instance.sh status         # Status of all
```

### Control Individual Instances
```bash
./control_instance.sh start 1        # Start instance 1
./control_instance.sh stop 2         # Stop instance 2
./control_instance.sh restart 3      # Restart instance 3
./control_instance.sh status 1       # Status of instance 1
```

### View Logs
```bash
./control_instance.sh logs 1         # Last 50 lines
./control_instance.sh logs 1 100     # Last 100 lines
./control_instance.sh follow 1       # Real-time follow (tail -f)

# Or use monitor script
./monitor_swarm_status.sh -f 1       # Follow instance 1
```

## 📊 Monitoring

### Real-time Dashboard
```bash
./monitor_swarm_status.sh --watch    # Updates every 5 seconds
```

### One-time Status Check
```bash
./monitor_swarm_status.sh            # Quick snapshot
./control_instance.sh status         # Alternative
```

### GPU Monitoring
```bash
watch -n 1 nvidia-smi                # Watch GPU usage
```

## ⚙️ Configuration

### Environment Variables

```bash
# Number of parallel instances (2-3 for 24GB GPU)
NUM_INSTANCES=3 ./run_multi_swarm.sh

# Disable Docker mode
USE_DOCKER=no ./run_multi_swarm.sh

# GPU memory per instance (MB)
GPU_MEMORY_PER_INSTANCE=7000 ./run_multi_swarm.sh

# Monitoring interval (seconds)
MONITOR_INTERVAL=30 ./run_multi_swarm.sh

# Disable auto-restart
AUTO_RESTART=no ./run_multi_swarm.sh
```

### Per-Instance Configs

Edit individual instance configs:
```bash
nano user/instance_1/configs/rg-swarm.yaml
nano user/instance_2/configs/rg-swarm.yaml
nano user/instance_3/configs/rg-swarm.yaml
```

## 📁 Directory Structure

```
user/
├── instance_1/              # Instance 1 files
│   ├── configs/
│   │   └── rg-swarm.yaml   # Editable config
│   ├── keys/               # Unique identity key
│   ├── logs/               # Training logs
│   └── modal-login/        # Auth data
├── instance_2/              # Instance 2 files
├── instance_3/              # Instance 3 files
└── logs/
    └── multi_swarm/        # Aggregated logs
        ├── instance_1.log
        ├── instance_2.log
        └── instance_3.log
```

## 🔧 Common Scenarios

### Starting Fresh Training
```bash
# Validate setup
./validate_multi_setup.sh

# Start 3 instances
./run_multi_swarm.sh

# In another terminal, monitor
./monitor_swarm_status.sh --watch
```

### Adding an Instance to Running Training
```bash
# In a separate terminal (while others run)
./control_instance.sh start 4
```

### Stopping One Instance
```bash
./control_instance.sh stop 2         # Stop instance 2 only
```

### Viewing Logs of Crashed Instance
```bash
./control_instance.sh logs 1 200     # Last 200 lines
```

### Emergency Stop All
```bash
./control_instance.sh stopall
# OR press Ctrl+C in the main run_multi_swarm.sh terminal
```

## 🐛 Troubleshooting

### Check What's Running
```bash
./control_instance.sh status
ps aux | grep swarm_launcher
nvidia-smi
```

### Kill Stuck Processes
```bash
pkill -f "rgym_exp.runner.swarm_launcher"
```

### Check Port Usage
```bash
lsof -i :3000
lsof -i :3001
lsof -i :3002
```

### GPU Out of Memory
```bash
# Stop all and restart with fewer instances
./control_instance.sh stopall
NUM_INSTANCES=2 ./run_multi_swarm.sh
```

### View All Logs
```bash
# Main process logs
tail -f user/logs/multi_swarm/instance_*.log

# Training logs
tail -f user/instance_1/logs/swarm_launcher.log
```

## 💡 Pro Tips

1. **Different Seeds**: Edit each instance config with different `seed` values for diversity
2. **Different Models**: Each instance can train a different model
3. **Stagger Starts**: The scripts automatically stagger starts by 3-5 seconds
4. **Monitor GPU**: Keep `nvidia-smi` running in a terminal to watch memory
5. **WandB Logs**: Each instance creates separate WandB runs for tracking
6. **Save Configs**: Backup configs before modifying: `cp rg-swarm.yaml rg-swarm.yaml.bak`

## 🎯 Recommended Setup for RTX 4090 (24GB)

```bash
# Conservative (safer, more memory per instance)
NUM_INSTANCES=2 GPU_MEMORY_PER_INSTANCE=10000 ./run_multi_swarm.sh

# Balanced (recommended)
NUM_INSTANCES=3 GPU_MEMORY_PER_INSTANCE=7000 ./run_multi_swarm.sh

# Aggressive (maximum utilization, monitor closely)
NUM_INSTANCES=3 GPU_MEMORY_PER_INSTANCE=6000 ./run_multi_swarm.sh
```

## 📞 Getting Help

```bash
# Script help
./control_instance.sh --help
./monitor_swarm_status.sh --help

# Validation
./validate_multi_setup.sh

# Full documentation
cat MULTI_INSTANCE_README.md
```

## 🔄 Workflow Example

**Terminal 1 (Main Process):**
```bash
./run_multi_swarm.sh
# Leave running, shows monitoring loop
```

**Terminal 2 (Monitoring):**
```bash
./monitor_swarm_status.sh --watch
# Real-time dashboard
```

**Terminal 3 (GPU Watch):**
```bash
watch -n 1 nvidia-smi
# Watch GPU utilization
```

**Terminal 4 (Control):**
```bash
# Make changes as needed
./control_instance.sh restart 2
./control_instance.sh logs 1
```

---

**Need more details?** See `MULTI_INSTANCE_README.md` for comprehensive documentation.

