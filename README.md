# TIG Stack using InfluxDB 3

A modern monitoring stack implementation using **Telegraf**, **InfluxDB 3**, and **Grafana** with **Nginx reverse proxy** and **InfluxDB Explorer** for comprehensive system monitoring and visualization.
The key of this project is the **automated deployment**. It will setup a development environment in minutes instead of hours if not days.

In a nutshell the deployment script conducts the following steps:
- Creates all required directories and initialization scripts and files.
- Creates an InfluxDB 3 Admin Token. The token is used to create a default database in InfluxDB 3. Configures Telegraf to use the token and to send metrics to the db.
- Automatically connects Influx Explorer to the InfluxDB 3 Core container. 
- Creates a Grafana InfluxDB Datasource and Dashboard. You can instantly view data!!

## Overview

This project provides a complete TIG (Telegraf, InfluxDB, Grafana) stack deployment using Docker Compose, featuring:

- **InfluxDB 3**: Modern time-series database
- **Telegraf**: Metrics collection agent
- **Grafana**: Data visualization and dashboards
- **InfluxDB Explorer**: Web-based database explorer
- **Nginx**: Reverse proxy with SSL termination
- **Automated Setup**: Complete environment configuration

## Architecture

```
Internet/External Sensors
         │
         ▼
┌────────────────────────────────────────────────────┐
│         frontend-network (172.20.0.0/16)           │
│  ┌─────────────┐              ┌──────────────────┐ │
│  │    Nginx    │◄─────────────┤    Telegraf      │ │
│  │   (Proxy)   │              │  (Collector)     │ │
│  └─────────────┘              └──────────────────┘ │
└────────────────────────────────────────────────────┘
         │                                  │
         │                                  │
         ▼                                  ▼
┌────────────────────────────────────────────────────┐
│         monitoring-network (172.21.0.0/16)         │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │    Nginx    │  │   Grafana    │  │ InfluxDB3  │ │
│  │   (Proxy)   │─▶│ (Dashboard)  │─▶│ (Database) │ │
│  └─────────────┘  └──────────────┘  └────────────┘ │
│                                         ▲          │
│  ┌──────────────────┐  ┌────────────────┘          │
│  │InfluxDB-Explorer │  │                           │
│  │  (Web UI)        │  │                           │
│  └──────────────────┘  │                           │
│                        │                           │
│  ┌──────────────────┐  │   ┌──────────────────┐    │
│  │   Telegraf       │──┘   │ docker-socket-   │    │
│  │  (Collector)     │      │     proxy        │    │
│  └──────────────────┘      └──────────────────┘    │
└────────────────────────────────────────────────────┘
```

## Features

- **Secure by Default**: Auto-generated SSL certificates and secure credentials
- **Production Ready**: Health checks, logging, and resource limits
- **Easy Setup**: Single script initialization
- **Customizable**: Extensive configuration options via environment variables
- **Modern Stack**: Latest versions of all components

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- OpenSSL available for certificate generation
- Bash shell environment

### Installation

1. **Clone or download the project files**
   ```bash
   # Ensure you have both files in the same directory:
   # - dev-setup-etig.sh
   # - docker-compose.yaml
   ```

2. **Run the setup script**
   ```bash
   chmod +x dev-setup-etig.sh
   ./dev-setup-etig.sh
   ```

3. **Start the stack**
   ```bash
   docker compose up -d
   ```

4. **Access the services**
   - **Grafana**: https://tig-grafana.tig-influx.test
   - **InfluxDB Explorer**: https://tig-explorer.tig-influx.test

### Host Configuration

Add these entries to your `/etc/hosts` file:
```
127.0.0.1    tig-grafana.tig-influx.test
127.0.0.1    tig-explorer.tig-influx.test
Or modify your (internal) DNS Server(s) like PiHole.
```

## Configuration

### Environment Variables

The setup script generates a comprehensive `.env` file with all necessary configuration. Key variables include:

| Variable | Description | Default |
|----------|-------------|---------|
| `TLD_DOMAIN` | Base domain | `tig-influx.test` |
| `INFLUXDB_HOST` | InfluxDB container name | `tig-influxdb3` |
| `INFLUXDB_BUCKET` | Default bucket name | `local_system` |
| `GRAFANA_ADMIN_USER` | Grafana admin username | `admin` |
| `TELEGRAF_COLLECTION_INTERVAL` | Metrics collection interval | `10s` |

### Credential Management

- Secure credentials are auto-generated and stored in `.credentials`
- Use `--regenerate-creds` flag to force new credential generation
- Default Grafana admin password is automatically generated

### SSL Certificates

- Self-signed certificates are automatically generated for development
- Certificates include proper Subject Alternative Names (SAN)
- Replace with CA-signed certificates for production use

## Services

### InfluxDB 3
- **Container**: `tig-influxdb3`
- **Port**: 8181 (internal)
- **Data**: Persisted in `./influxdb_data`
- **Config**: `./influxdb/config/`

### Telegraf
- **Container**: `tig-telegraf`
- **Metrics**: System CPU, memory, disk, network
- **Config**: `./telegraf/telegraf.conf`
- **Interval**: 10 seconds (configurable)

### Grafana
- **Container**: `tig-grafana`
- **Port**: 3000 (internal)
- **Data**: Persisted in `./grafana_data`
- **Config**: `./grafana_config/grafana.ini`
- **Provisioning**: Automatic datasource and dashboard setup

### InfluxDB Explorer
- **Container**: `tig-explorer`
- **Port**: 80 (internal)
- **Purpose**: Web-based database exploration and querying

### Nginx
- **Container**: `tig-nginx`
- **Ports**: 80 (redirect), 443 (HTTPS)
- **SSL**: Automatic certificate management
- **Features**: Rate limiting, security headers, compression

## Initialization Scripts

The stack includes automated initialization scripts that run on first deployment:

### wrapper.sh
Main orchestration script that executes initialization tasks in sequence:
- Runs `create-database.sh` to initialize the InfluxDB database
- Runs `grafana-token.sh` to set up Grafana authentication

**Container**: `tig-scripts-init` (runs once, auto-removes on completion)

### create-database.sh
Automated InfluxDB database creation script that:
- Installs required tools (curl, jq) in the Alpine container
- Extracts authentication token from `/etc/influxdb3/auto-admin-token.json`
- Waits for InfluxDB to become healthy (configurable timeout)
- Creates the initial database bucket using InfluxDB 3 API
- Handles error cases (already exists, authentication failures, etc.)
- Provides detailed logging of the creation process

**Default Database**: `local_system` (configured via `INFLUXDB_BUCKET`)

### grafana-token.sh
Grafana Service Account and API token creation script that:
- Installs required tools if not already installed (curl, jq)
- Waits for Grafana to become healthy before proceeding
- Tests authentication with admin credentials
- Creates a Grafana Service Account with Admin role
- Generates an API token for the service account
- Stores the token securely in `/app/grafana_SA_Token` with metadata
- Exports `GRAFANA_API_TOKEN` environment variable for subsequent use

**Service Account**: `tig-grafana-sa` (configured via `GRAFANA_SA_NAME`)  
**Token Name**: `tig-grafana-sa-token` (configured via `GRAFANA_TOKEN_NAME`)

### Script Execution Flow

```
Docker Compose Start
        ↓
    InfluxDB Healthy
        ↓
  scripts-init Container
        ↓
    wrapper.sh
        ↓
   ┌────────────────┐
   │                │
   ▼                ▼
create-database  grafana-token
   │            │
   └────────────┘
         ↓
    Initialization Complete
    (Container Auto-Removes)
```

## Directory Structure

```
├── dev-setup-etig.sh         # Setup script
├── .env                      # Environment variables 
├── .credentials              # Secure credentials 
├── certs/                    # TLD Certificates 
├── docker-compose.yml        # Docker Compose file 
├── grafana_config/           # Grafana configuration
│   └── grafana.ini           # Custom grafana.ini
├── grafana_data/             # Persistent Grafana DB
├── grafana_provisioning/     # Auto-provisioned 
│   ├── dashboards/
│   │   ├── dashboards.yml    # Load dashboards from
│   │   └── my-dashboard.json # Dashboards 
│   └── datasources/
│       └── datasources.yml   # Datasource definitions
├── influxExplorer/           # Influx Explorer 
│   ├── config/
│   │   └── config.json       # InfluxDB3 Server con.
│   └──  db/
│       └── sqlite.db         # Influx Explorer db 
├── influxdb/                 # InfluxDB3 config files
│   └── config/               # Admin Token
├── influxdb_data/            # Persistant InfluxDB3 
│   ├── plugins/
│   │   └── .venv/            # Python virtual runtime
│   └── writer1/              # InfluxDB3 Databases 
├── nginx/                    # Nginx configuration
│    ├── nginx.conf
│    ├── tig-influx.test.crt
│    └── tig-influx.test.key
│    └── conf.d/
│       └── default.conf
├── scripts/                  # Initialization scripts
│    ├── wrapper.sh
│    └── create-database.sh
│    └── grafana-token.sh
└── telegraf/                 # Telegraf configuration
     └── telegraf.conf
```

## Management

### Starting Services
```bash
docker compose up -d
```

### Stopping Services
```bash
docker compose down
```

### Viewing Logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f grafana
```

### Health Checks
```bash
# Check service status
docker compose ps

# Individual health checks
docker compose exec nginx nginx -t
curl -k https://tig-grafana.tig-influx.test/api/health
```

### Updating Configuration
```bash
# Regenerate credentials and certificates
./tessie-dev-setup-tig.sh --regenerate-creds

# Restart affected services
docker compose restart
```

## Security Features

### Network Security
- Isolated Docker networks (frontend/monitoring)
- Docker socket proxy for secure container access
- No privileged containers

### SSL/TLS
- Modern TLS 1.2/1.3 only
- Secure cipher suites
- HSTS headers
- Self-signed certificates for development

### Access Control
- Rate limiting on all endpoints
- Security headers (CSP, XSS protection, etc.)
- Secure credential generation and storage
- No default passwords

## Troubleshooting

### Common Issues

**Certificate Warnings**
- Expected for self-signed certificates
- Add certificates to browser trust store for development

**Permission Errors**
- Ensure proper ownership: `chown -R $(id -u):$(id -g) .`
- Check directory permissions in setup script output

**Service Health Check Failures**
- Check logs: `docker compose logs [service-name]`
- Verify network connectivity between containers
- Ensure all required environment variables are set

**Database Connection Issues**
- Verify InfluxDB is healthy: `docker compose ps`
- Check token configuration in datasources
- Review InfluxDB logs for authentication errors

### Debugging

```bash
# Enable debug logging
docker compose logs --tail=100 -f

# Access container shells
docker compose exec grafana /bin/bash
docker compose exec influxdb /bin/bash

# Test network connectivity
docker compose exec telegraf ping influxdb
docker compose exec grafana ping influxdb
```

## Development

### Customization

**Modify Environment Variables**
```bash
# Edit .env file
vim .env

# Restart services
docker compose restart
```

**Update Configurations**
```bash
# Edit service configs
vim telegraf/telegraf.conf
vim grafana_config/grafana.ini

# Restart specific service
docker compose restart telegraf
```

**Add Custom Dashboards**
- Place JSON files in `./grafana_provisioning/dashboards/`
- Restart Grafana: `docker compose restart grafana`

### Production Deployment

For production use:

1. **Replace SSL Certificates**
   - Obtain CA-signed certificates
   - Update certificate paths in nginx configuration

2. **Secure Network Access**
   - Bind ports to localhost: `127.0.0.1:443:443`
   - Use proper firewall rules
   - Implement VPN or authenticated access

3. **Resource Management**
   - Add resource limits to docker-compose.yaml
   - Implement log rotation
   - Monitor disk usage

4. **Backup Strategy**
   - Regular backup of `./grafana_data`
   - InfluxDB data backup procedures
   - Configuration backup

## Authors and Credits

- **Author**: Edward Voermans (edward@voermans.com)
- **Credits**: Based on work by Suyash Joshi (sjoshi@influxdata.com)
- **Source**: [TIG-Stack-using-InfluxDB-3](https://github.com/InfluxCommunity/TIG-Stack-using-InfluxDB-3)

## License

This project builds upon MIT license.

## Support

For issues and questions:
- Check the troubleshooting section above
- Review logs using `docker compose logs`
- Consult the original project documentation
- Contact: edward@voermans.com

---

*Generated for TIG Stack v4.0.3*  
*Last Updated: September 2025*