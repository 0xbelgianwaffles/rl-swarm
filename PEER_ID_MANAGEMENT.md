# Peer ID Management in RL-Swarm Multi-Instance Setup

## 🔍 Critical Finding: Peer ID Uniqueness Requirement

### The Check
When any RL-Swarm instance starts, **hivemind performs a network check** to ensure the peer identity isn't already in use:

**Location:** `/usr/local/lib/python3.10/dist-packages/hivemind/p2p/p2p_daemon.py`

```python
if await cls.is_identity_taken(identity_path, ...):
    raise P2PDaemonError(
        f"Identity from `{identity_path}` is already taken by another peer"
    )
```

### How It Works
1. **Reads the identity file** (e.g., `swarm.pem`) and extracts the Peer ID
2. **Attempts to connect** to that Peer ID on the network using an anonymous connection
3. **If connection succeeds** → Peer ID is already in use → **FAILS** with `P2PDaemonError`
4. **If connection fails** (ControlFailure) → Peer ID is free → **CONTINUES**

### Registration vs. Network Check
There are **TWO separate checks**:

#### 1. Network-Level Check (Hivemind)
- **Location:** Hivemind's P2P daemon startup
- **Purpose:** Prevent multiple instances from using the same identity file
- **Error:** `P2PDaemonError: Identity from {path} is already taken by another peer`
- **This fails the entire instance startup**

#### 2. On-Chain Registration Check (Coordinator)
- **Location:** `rgym_exp/src/coordinator.py:21-36`
- **Purpose:** Register peer ID with the smart contract
- **Error:** `PeerIdAlreadyRegistered` (HTTP 400)
- **This is handled gracefully** - logs a message and continues:
  ```python
  if err_name != "PeerIdAlreadyRegistered":
      raise
  get_logger().info(f"Peer ID [{peer_id}] is already registered! Continuing.")
  ```

## ✅ Our Multi-Instance Solution

### Current Implementation Status

#### `run_multi_swarm_auto.sh` (Single GPU, Multiple Instances)
**Status:** ✅ **CORRECT**

Creates unique identity files per instance:
```bash
export IDENTITY_PATH="$instance_dir/keys/swarm_${instance_num}.pem"
```

**Directory structure:**
```
/root/rl-swarm/user/
├── instance_1/
│   └── keys/swarm_1.pem     # Unique peer ID
├── instance_2/
│   └── keys/swarm_2.pem     # Unique peer ID
└── instance_3/
    └── keys/swarm_3.pem     # Unique peer ID
```

#### `run_multi_swarm_auto_8pod.sh` (8 GPUs, 3 Instances Each)
**Status:** ✅ **CORRECT**

Each GPU runs its own `run_multi_swarm_auto.sh` with isolated directories:
```bash
export GPU_USER_DIR="$ROOT/user/gpu_${gpu_id}"
```

**Directory structure:**
```
/root/rl-swarm/user/
├── gpu_0/
│   ├── instance_1/keys/swarm_1.pem
│   ├── instance_2/keys/swarm_2.pem
│   └── instance_3/keys/swarm_3.pem
├── gpu_1/
│   ├── instance_1/keys/swarm_1.pem  # Different file, unique peer ID
│   ├── instance_2/keys/swarm_2.pem
│   └── instance_3/keys/swarm_3.pem
└── ... (gpu_2 through gpu_7)
```

**Total:** 24 unique peer identities (8 GPUs × 3 instances)

## 🚨 Common Pitfalls to Avoid

### ❌ WRONG: Using the same identity file
```bash
# This will FAIL on the 2nd instance!
export IDENTITY_PATH="/root/rl-swarm/swarm.pem"
# Start instance 1 ✓
# Start instance 2 ✗ P2PDaemonError: Identity already taken
```

### ❌ WRONG: Sharing identity directory between instances
```bash
# Both instances pointing to same file
INSTANCE_1_IDENTITY="/shared/swarm_1.pem"
INSTANCE_2_IDENTITY="/shared/swarm_1.pem"  # WRONG!
```

### ✅ CORRECT: Unique identity per instance
```bash
# Each instance has its own identity file
INSTANCE_1_IDENTITY="/root/rl-swarm/user/instance_1/keys/swarm_1.pem"
INSTANCE_2_IDENTITY="/root/rl-swarm/user/instance_2/keys/swarm_2.pem"
INSTANCE_3_IDENTITY="/root/rl-swarm/user/instance_3/keys/swarm_3.pem"
```

## 📋 Verification Checklist

Before running multi-instance setups, verify:

- [ ] Each instance has `IDENTITY_PATH` set to a **unique file path**
- [ ] Identity files are in **instance-specific directories**
- [ ] No two instances share the same `.pem` file
- [ ] If an instance fails with "Identity already taken", check for duplicate paths

## 🔧 Debugging Identity Issues

### Check if identity is in use:
```bash
# List all running instances and their identity paths
ps aux | grep swarm_launcher
```

### Verify unique identity files exist:
```bash
# For run_multi_swarm_auto.sh
find /root/rl-swarm/user/instance_* -name "*.pem"

# For run_multi_swarm_auto_8pod.sh
find /root/rl-swarm/user/gpu_* -name "*.pem"
```

### Check logs for identity conflicts:
```bash
# Look for the "already taken" error
grep -r "already taken" /root/rl-swarm/user/logs/

# Look for the identity checking message
grep -r "Checking that identity" /root/rl-swarm/user/logs/
```

## 📖 Related Documentation

From `README.md` (lines 123-148):

### Identity Management Guidelines

**Multiple nodes with same EOA:**
- Sign up each node with the **same email address**
- Each node gets a **different `swarm.pem`** (unique peer ID)
- All peer IDs linked to the same EOA wallet

**Important scenarios:**

✅ **Works:**
- First time run with new email + new swarm.pem
- Re-run with existing swarm.pem + original email

❌ **Doesn't work:**
- Keep swarm.pem but use different email than original
- Multiple instances sharing the same swarm.pem file

## 🎯 Summary

| Component | Responsibility | Error Type | Handling |
|-----------|---------------|------------|----------|
| **Hivemind P2P** | Network-level uniqueness | `P2PDaemonError` | **Fails startup** |
| **Coordinator** | On-chain registration | `PeerIdAlreadyRegistered` | **Logs & continues** |

**Key Takeaway:** Every running instance **MUST** have its own unique identity file (`.pem`). Our multi-instance scripts handle this correctly by creating separate identity files per instance.

