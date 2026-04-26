# elkstack-dockerized

A simple project that dockerizes the Elastic Stack (Elasticsearch + Kibana) for ease of deployment.

## Prerequisites

- Docker and Docker Compose installed
- Git (for cloning the repository)

## Quick Start

### Option 1: Using Pre-built Images

1. Create a `docker-compose.yml` file with the configuration from this repository
2. Copy `env.example` to `.env` and configure your settings:
   ```bash
   cp env.example .env
   ```
3. this is optional but you can specify the password you want to use
4. Start the stack:
   ```bash
   docker compose up -d
   ```

### Option 2: Build Locally (Development)

1. Clone the repository:
   ```bash
   git clone https://github.com/onixldlc/elkstack.git
   cd elkstack
   ```
2. Copy and configure environment variables:
   ```bash
   cp env.example .env
   ```
3. Build and start the containers:
   ```bash
   docker compose -f docker-compose-dev.yml up -d --build
   ```

## Configuration

### Environment Variables

Create a `.env` file based on `env.example`:

| Variable | Description | Default |
|----------|-------------|---------|
| `ELASTIC_PASSWORD` | Password for the `elastic` user | *(optional - will create random password if empty)* |
| `KIBANA_HOST` | Hostname for Kibana server | `kibana` |
| `KIBANA_PORT` | Port for Kibana server | `5601` |
| `ELASTICSEARCH_URLS` | Elasticsearch URLs for Kibana/Logstash to connect | `["https://elasticsearch:9200"]` |
| `IGNORE_DISK_CHECK` | Set to `true` to let Logstash start even when disk ≥ 90% (**not recommended**) | `false` |

### Ports

| Service | Port | Access |
|---------|------|--------|
| Elasticsearch | 9200 | `https://localhost:9200` |
| Kibana | 5601 | `https://localhost:5601` |
| Logstash | - | - |

> **Note:** By default, ports are bound to `127.0.0.1` only for security. Modify the docker-compose file to expose externally if needed.

### Volumes

| Service | Container Path | Description |
|---------|---------------|-------------|
| Elasticsearch | `/var/lib/elasticsearch` | Data storage |
| Elasticsearch | `/var/log/elasticsearch` | Log files |
| Elasticsearch | `/tmp/config` | Configuration files |
| Kibana | `/var/log/kibana` | Log files |
| Kibana | `/etc/kibana` | Configuration files |
| Logstash | `/tmp/config` | Configuration files |

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

## Testing

Two test scenarios live under `test/`:

```bash
# Test 1 — all services start, Logstash proceeds normally
./test/run-normal.sh

# Test 2 — disk at ~92%, Logstash should detect it and refuse to start
./test/run-disk-limit.sh
```

Test 2 uses a Podman tmpfs named volume (2 GB, pre-filled to ~92%) — no host disk is touched.

Test data goes to `test/data/` (gitignored). To clean up after tests:

```bash
podman compose -f test/docker-compose-normal.yml --project-name elkstack-test-normal down --volumes
podman compose -f test/docker-compose-disk-limit.yml --project-name elkstack-test-disk-limit down --volumes
podman unshare rm -rf test/data/   # ES files are owned by container subuid — needs unshare to delete
```