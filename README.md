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
| `DISCOVERY_SEED_HOSTS` | JSON array of node hostnames for cluster discovery (multi-node only). When set on Kibana/Logstash, `ELASTICSEARCH_URLS` is auto-derived as `https://<host>:9200` per entry | *(unset → single-node)* |
| `CLUSTER_INITIAL_MASTER_NODES` | JSON array of node names eligible to bootstrap the cluster on first start (multi-node only) | *(unset)* |
| `NODE_NAME` | Per-node identifier used as `node.name` in the cluster (multi-node only) | `elasticsearch` |
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

Logstash refuses to start if Elasticsearch disk usage is ≥ 90% on any data node. See [CAVEAT.md](CAVEAT.md#logstash-disk-safety-check) for full details, bypass options, and security rationale.

## Multi-Node Cluster Deployment

The stack supports running Elasticsearch as a 2+ node cluster. Two compose files are provided:

| File | Purpose |
|------|---------|
| `docker-compose-mnode.yml` | Multi-node, pulls pre-built images from `ghcr.io/onixldlc/*` |
| `docker-compose-dev-mnode.yml` | Multi-node, builds locally from `./elastic`, `./kibana`, `./logstash` |

### Quick start

```bash
cp env.example .env
docker compose -f docker-compose-mnode.yml up -d
```

This launches two ES nodes (`elasticsearch-node1`, `elasticsearch-node2`) plus Kibana and Logstash, all wired to the cluster via `DISCOVERY_SEED_HOSTS`. Kibana and Logstash auto-derive their `ELASTICSEARCH_URLS` from the seed hosts — no extra config needed.

See [CAVEAT.md](CAVEAT.md#multi-node-cluster) for how cluster mode works internally and how to add more nodes.

## Testing

Four test scenarios live under `test/`:

```bash
# Test 1 — single-node, all services healthy, Logstash proceeds
./test/run-normal.sh

# Test 2 — single-node, disk at ~92%, Logstash should refuse to start
./test/run-disk-limit.sh

# Test 3 — 2-node cluster, both nodes healthy, Logstash proceeds
./test/run-multi-node-normal.sh

# Test 4 — 2-node cluster, node2 at ~92%, Logstash should refuse to start
./test/run-multi-node.sh
```

Tests 2 and 4 use a Podman tmpfs named volume (2 GB, pre-filled to ~92%) — no host disk is touched.

Test data goes to `test/data/` (gitignored). To clean up after tests:

```bash
podman compose -f test/docker-compose-normal.yml --project-name elkstack-test-normal down --volumes
podman compose -f test/docker-compose-disk-limit.yml --project-name elkstack-test-disk-limit down --volumes
podman compose -f test/docker-compose-multi-node-normal.yml --project-name elkstack-test-multi-normal down --volumes
podman compose -f test/docker-compose-multi-node.yml --project-name elkstack-test-multi down --volumes
podman unshare rm -rf test/data/   # ES files are owned by container subuid — needs unshare to delete
```