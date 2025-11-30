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
| `ELASTICSEARCH_URLS` | Elasticsearch URLs for Kibana to connect | `["https://elasticsearch:9200"]` |

### Ports

| Service | Port | Access |
|---------|------|--------|
| Elasticsearch | 9200 | `https://localhost:9200` |
| Kibana | 5601 | `https://localhost:5601` |

> **Note:** By default, ports are bound to `127.0.0.1` only for security. Modify the docker-compose file to expose externally if needed.

### Volumes

| Service | Container Path | Description |
|---------|---------------|-------------|
| Elasticsearch | `/var/lib/elasticsearch` | Data storage |
| Elasticsearch | `/var/log/elasticsearch` | Log files |
| Elasticsearch | `/tmp/config` | Configuration files |
| Kibana | `/var/log/kibana` | Log files |
| Kibana | `/etc/kibana` | Configuration files |