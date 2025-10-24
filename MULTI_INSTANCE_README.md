# Multi-Instance RL Swarm Training

This directory contains scripts to run multiple RL swarm training instances in parallel to maximize GPU utilization.

## Overview

The multi-instance setup allows you to:
- Run 2-3 parallel training instances on a single GPU (e.g., RTX 4090 with 24GB)
- Monitor GPU usage, process health, and logs in real-time
- Automatically restart failed instances
- Manage separate configurations and logs for each instance

## Quick Start

### 1. Basic Multi-Instance Training (3 instances)

```bash
chmod +x run_multi_swarm.sh monitor_swarm_status.sh
./run_multi_swarm.sh
```

This will:
- Create 3 separate training instances
- Assign unique ports (3000, 3001, 3002)
- Create separate log directories for each instance
- Start monitoring all instances

### 2. Custom Configuration

You can customize the behavior with environment variables:

```bash
# Run 2 instances instead of 3
NUM_INSTANCES=2 ./run_multi_swarm.sh

# Disable Docker mode (run directly)
USE_DOCKER=no ./run_multi_swarm.sh

# Adjust GPU memory allocation per instance
GPU_MEMORY_PER_INSTANCE=6000 ./run_multi_swarm.sh

# Change monitoring interval (seconds)
MONITOR_INTERVAL=30 ./run_multi_swarm.sh

# Disable auto-restart
AUTO_RESTART=no ./run_multi_swarm.sh
```

### 3. Monitor Running Instances

In a separate terminal, you can monitor the status:

```bash
# One-time status check
./monitor_swarm_status.sh

# Continuous monitoring (updates every 5 seconds)
./monitor_swarm_status.sh --watch

# Follow logs for a specific instance
./monitor_swarm_status.sh -f 1  # Follow instance 1
./monitor_swarm_status.sh -f 2  # Follow instance 2
```

## Directory Structure

After running the multi-instance setup, you'll have:

```
user/
├── instance_1/
│   ├── configs/
│   │   └── rg-swarm.yaml
│   ├── keys/
│   │   └── swarm_1.pem
│   ├── logs/
│   └── modal-login/
├── instance_2/
│   ├── configs/
│   ├── keys/
│   ├── logs/
│   └── modal-login/
├── instance_3/
│   └── ...
└── logs/
    └── multi_swarm/
        ├── instance_1.log
        ├── instance_2.log
        └── instance_3.log
```

## Configuration

### Per-Instance Configuration

Each instance has its own configuration file at:
```
user/instance_N/configs/rg-swarm.yaml
```

You can customize each instance independently by editing these files. Common adjustments:

1. **Model Selection**: Different models per instance
```yaml
trainer:
  models:
    - _target_: transformers.AutoModelForCausalLM.from_pretrained
      pretrained_model_name_or_path: "Gensyn/Qwen2.5-1.5B-Instruct"
```

2. **Training Parameters**: Different hyperparameters
```yaml
training:
  num_generations: 2
  num_transplant_trees: 2
  seed: 42  # Change seed for diversity
```

3. **Resource Limits**: Adjust batch sizes, etc.
```yaml
training:
  dtype: 'float16'  # Use mixed precision to save memory
```

### GPU Memory Optimization

For a 24GB GPU (RTX 4090):
- **Conservative (2 instances)**: Set `NUM_INSTANCES=2` for ~8-10GB per instance
- **Balanced (3 instances)**: Set `NUM_INSTANCES=3` for ~6-7GB per instance  
- **Aggressive (4+ instances)**: Possible with smaller models and careful tuning

Monitor GPU usage with:
```bash
watch -n 1 nvidia-smi
```

## Features

### 1. Automatic Health Monitoring

The main script monitors:
- Process status (running/stopped)
- GPU utilization and memory
- Log file activity and errors
- Automatic restart on failure (if enabled)

### 2. Graceful Shutdown

Press `Ctrl+C` to:
- Send termination signal to all instances
- Wait for graceful shutdown (10 seconds)
- Force-kill if necessary
- Preserve all logs

### 3. Separate Logging

Each instance maintains:
- Separate log file in `user/logs/multi_swarm/`
- Training metrics in `user/instance_N/logs/`
- WandB runs (if enabled)

### 4. Port Management

Instances automatically use sequential ports:
- Instance 1: Port 3000
- Instance 2: Port 3001
- Instance 3: Port 3002

## Monitoring Output

The monitor script shows:

```
╔════════════════════════════════════════════════════════════════════╗
║         RL-SWARM MULTI-INSTANCE STATUS DASHBOARD                  ║
╚════════════════════════════════════════════════════════════════════╝

┌─ GPU STATUS ──────────────────────────────────────────────────────┐
│ GPU 0: NVIDIA GeForce RTX 4090
│   Utilization: 85%
│   Memory: 18432MB / 24576MB (75%)
│   Temperature: 72°C
└───────────────────────────────────────────────────────────────────┘

┌─ SWARM INSTANCES ─────────────────────────────────────────────────┐
│
│ ═══ Instance 1 ═══
│   Status: ✓ RUNNING (PID: 12345)
│   CPU: 45.2% | Memory: 12.3% | Uptime: 01:23:45
│   Log: 124M (updated: 2025-10-14 02:30:15)
│   Recent activity:
│     [2025-10-14 02:30:15] Training round 156 complete
│     [2025-10-14 02:30:12] Model checkpoint saved
│     [2025-10-14 02:30:10] Reward: 0.875
...
```

## Troubleshooting

### Issue: Instance won't start

1. Check GPU memory availability:
   ```bash
   nvidia-smi
   ```

2. Reduce number of instances:
   ```bash
   NUM_INSTANCES=2 ./run_multi_swarm.sh
   ```

3. Check individual instance logs:
   ```bash
   ./monitor_swarm_status.sh -f 1
   ```

### Issue: Out of GPU memory

1. Kill all instances:
   ```bash
   pkill -f "rgym_exp.runner.swarm_launcher"
   ```

2. Restart with fewer instances:
   ```bash
   NUM_INSTANCES=2 ./run_multi_swarm.sh
   ```

3. Or use smaller models in configs

### Issue: Port already in use

Check if previous instances are still running:
```bash
lsof -i :3000
lsof -i :3001
lsof -i :3002
```

Kill them if needed:
```bash
kill -9 $(lsof -t -i:3000)
```

### Issue: Instances keep restarting

1. Disable auto-restart to debug:
   ```bash
   AUTO_RESTART=no ./run_multi_swarm.sh
   ```

2. Check logs for errors:
   ```bash
   tail -f user/logs/multi_swarm/instance_1.log
   ```

## Best Practices

1. **Start Small**: Begin with 2 instances and monitor GPU usage
2. **Monitor Regularly**: Use watch mode to catch issues early
3. **Stagger Starts**: The script automatically staggers starts by 5 seconds
4. **Save Checkpoints**: Configure frequent checkpoints in case of crashes
5. **Use WandB**: Enable WandB for better experiment tracking across instances
6. **Different Seeds**: Use different random seeds for each instance to increase diversity

## Advanced Usage

### Running with Docker

```bash
USE_DOCKER=yes ./run_multi_swarm.sh
```

This will use the docker-compose configuration for containerized training.

### Custom Instance Configuration

1. Edit the base config:
   ```bash
   nano rgym_exp/config/rg-swarm.yaml
   ```

2. Or edit individual instance configs:
   ```bash
   nano user/instance_1/configs/rg-swarm.yaml
   nano user/instance_2/configs/rg-swarm.yaml
   ```

### Experiment Tracking

Each instance can push to different HuggingFace repos:
1. Set different `HUGGINGFACE_ACCESS_TOKEN` per instance
2. Modify the wrapper script generation in `run_multi_swarm.sh`

## Integration with Original Script

The multi-instance setup is designed to coexist with the original `run_rl_swarm.sh`:

- **Single instance training**: Use `./run_rl_swarm.sh` (unchanged)
- **Multi-instance training**: Use `./run_multi_swarm.sh` (new)
- Both use the same codebase and dependencies
- Configs are isolated per instance to avoid conflicts

## Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `NUM_INSTANCES` | 3 | Number of parallel instances (2-3 recommended for 24GB GPU) |
| `USE_DOCKER` | yes | Use Docker containers ("yes" or "no") |
| `GPU_MEMORY_PER_INSTANCE` | 8000 | Estimated MB per instance for capacity planning |
| `MONITOR_INTERVAL` | 60 | Seconds between health checks |
| `AUTO_RESTART` | yes | Automatically restart failed instances |

## Performance Tips

1. **Use Float16**: Set `dtype: 'float16'` in configs to reduce memory
2. **Smaller Batches**: Reduce batch sizes if OOM errors occur
3. **Model Selection**: Use smaller models (0.5B-1.5B) for more instances
4. **CPU Offloading**: Configure CPU offloading for large models
5. **Gradient Checkpointing**: Enable to reduce memory at cost of speed

## Support

For issues or questions:
1. Check logs: `user/logs/multi_swarm/`
2. Monitor GPU: `nvidia-smi`
3. Review original docs: `README.md`
4. Check GitHub issues: https://github.com/gensyn-ai/rl-swarm

---

**Note**: This is a custom multi-instance wrapper around the original RL-Swarm setup. The original single-instance script (`run_rl_swarm.sh`) remains unchanged and fully functional.

