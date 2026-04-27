# Caveats & Inner Workings

## Logstash Disk Safety Check

Logstash **refuses to start** if Elasticsearch disk usage is ≥ **90%** on any data node.

### Why

Elasticsearch activates flood-stage watermark at ~95% disk, blocking all index writes. Starting Logstash at 90%+ risks immediate write failures, no recovery headroom, and potential index corruption if Elasticsearch is killed mid-write. This check runs regardless of whether the flood-stage watermark has been manually increased.

### How it works

1. On first boot, Elasticsearch creates a read-only `logstash_monitor` user with `cluster:monitor` privilege only (no write or index access)
2. The monitor credential is written to the internal `pub-share` volume (separate from the `share` volume that holds the `elastic` superuser password — Logstash never sees superuser credentials)
3. Before starting, Logstash queries `GET /_cat/allocation?h=disk.percent`
4. If the highest disk percentage across all nodes is ≥ 90, Logstash exits

### What you will see

**Normal startup (disk < 90%):**
```
Checking Elasticsearch disk usage...
Elasticsearch disk usage: 42%. Proceeding.
Starting Logstash...
```

**Blocked startup (disk ≥ 90%):**
```
Checking Elasticsearch disk usage...
ERROR: Elasticsearch disk at 93%. Refusing to start — protect data integrity.
       Free up disk space or set IGNORE_DISK_CHECK=true to bypass (not recommended).
```

### Bypassing the check

> **Warning:** Only use this if you understand the risk. Logstash running at ≥ 90% disk will hit Elasticsearch flood-stage quickly, causing write rejections and potential data loss.

Set `IGNORE_DISK_CHECK=true` in the Logstash service environment:

```yaml
services:
  logstash:
    environment:
      - IGNORE_DISK_CHECK=true
```

Logstash will log a warning and start anyway:
```
WARNING: Elasticsearch disk at 93%. IGNORE_DISK_CHECK=true — proceeding anyway.
         This risks Elasticsearch data corruption. Resolve disk pressure ASAP.
```

### Security: why two volumes?

| Volume | Mounted by | Contains |
|--------|-----------|---------|
| `share` | ES + Kibana only | `elastic` superuser password, TLS certificates |
| `pub-share` | ES + Logstash only | `logstash_monitor` read-only credential |

Never mount `share` into Logstash. A compromised Logstash container must not be able to reach the superuser password.

---

## Multi-Node Cluster

### How cluster mode is activated

Setting `DISCOVERY_SEED_HOSTS` on the Elasticsearch service (and `CLUSTER_INITIAL_MASTER_NODES` for first-start bootstrap) flips the entrypoint out of single-node mode:

- `discovery.type: single-node` is removed from `elasticsearch.yml`
- `discovery.seed_hosts` and `cluster.initial_master_nodes` are written from env vars
- The shared `/tmp/config` volume across nodes ensures one TLS cert and one `elastic` superuser password are generated, then reused by every node

The entrypoint uses an atomic `mkdir`-based leader lock so only one node performs first-time init (cert/keystore/yml generation). Followers wait for `.init_complete` before proceeding. The `logstash_monitor` user is created exclusively by the elected cluster master after ES forms.

### Adding more nodes

Copy a node block and bump the name:

```yaml
elasticsearch-node3:
  container_name: elasticsearch-node3
  image: ghcr.io/onixldlc/elasticsearch:latest
  volumes:
    - ./elastic/node3/data:/var/lib/elasticsearch
    - ./elastic/node3/logs:/var/log/elasticsearch
    - ./elastic/shared/config:/tmp/config
    - share:/tmp/share
    - pub-share:/tmp/pub-share
  environment:
    - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
    - NODE_NAME=node3
    - 'DISCOVERY_SEED_HOSTS=["elasticsearch-node1","elasticsearch-node2","elasticsearch-node3"]'
    - 'CLUSTER_INITIAL_MASTER_NODES=["node1","node2","node3"]'
```

Then update `DISCOVERY_SEED_HOSTS` (and `CLUSTER_INITIAL_MASTER_NODES`) on every other service to include the new node.
