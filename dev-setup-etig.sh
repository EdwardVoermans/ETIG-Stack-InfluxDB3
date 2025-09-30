#!/bin/bash
##################################################################################################################################
# Script Name : dev-setup-etig.sh
# Description : This script creates all required directories and sets proper permissions
#               for the Docker Compose TIG stack (Telegraf, InfluxDB, Influx Explorer, Grafana + Nginx).
#               It also creates init files, tokens, self signed certificates and scripts. 
# Note        : Development Environment for testing purposes
# Author      : Edward Voermans [ edward@voermans.com ]
# Credits     : Suyash Joshi (sjoshi@influxdata.com) 
#             : Github published https://github.com/InfluxCommunity/TIG-Stack-using-InfluxDB-3/tree/main
# Created On  : 22-08-2025
# Last Update : 30-09-2025
# Version     : 4.2
# Target      : tig-influx.test Development
# Usage       :
#   ./dev-setup-etig.sh [--regenerate-creds] 
#
# Requirements:
#   - Docker must be setup and working
#   - Run this script from the same directory as your docker-compose.yml file
#   - openssl command must be available for credential generation
#
# Notes       :
#   - Run with sudo if accessing restricted files (Like chown -R)
#   - Tested on Raspberry Pi 4 / DietPi v9.16.3
#   - Use --regenerate-creds to force new credential generation
##################################################################################################################################

set -e  # Exit on any error

#### First step, set VARs ########################################################################################################
#################################### Export VARs #################################################################################
############### VARs are used during config file creation and for .env file for consistancy ######################################
############### Edit this section to fit your own specific requirements ##########################################################
set_environment_variables() {
    ##### General
    export TLD_DOMAIN=tig-influx.test
    export TIMEOUT=120
    export HEALTH_CHECK_INTERVAL=5
    ##### NGINX Configuration
    export NGINX_HOST=tig-nginx
    export URL_GRAFANA=tig-grafana.tig-influx.test
    export URL_INFLUXDB_EXPLORER=tig-explorer.tig-influx.test
    export CERT_CRT=tig-influx.test.crt
    export CERT_KEY=tig-influx.test.key
    ##### InfluxDB Configuration
    export INFLUXDB_HTTP_PORT=8181
    export INFLUXDB_HOST=tig-influxdb3
    export INFLUXDB_ORG=etig-influx.test
    export INFLUXDB_BUCKET=local_system
    export INFLUXDB_NODE_ID=writer1
    export INFLUXDB_TOKEN_FILE=/etc/influxdb3/auto-admin-token.json
    ##### Grafana Configuration
    export GRAFANA_HOST=tig-grafana
    export GRAFANA_PORT=3000
    export GRAFANA_ADMIN_USER=admin
    export GRAFANA_SA_NAME=tig-grafana-sa 
    export GRAFANA_TOKEN_NAME=tig-grafana-sa-token    
    ##### Telegraf Configuration
    export TELEGRAF_HOST=tig-telegraf
    export TELEGRAF_COLLECTION_INTERVAL=10s
    ##### InfluxDB Explorer Configuration
    export INFLUXDB_EXPLORER_HOST=tig-explorer
    export INFLUXDB_EXPLORER_PORT=80
}
##################################################################################################################################
##################################################################################################################################
##################################################################################################################################

#### Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#### Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${SCRIPT_DIR}"
LOG_FILE="${BASE_DIR}/setup.log"
REGENERATE_CREDS=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --regenerate-creds)
            REGENERATE_CREDS=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--regenerate-creds]"
            echo "  --regenerate-creds  Force regeneration of all credentials"
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
done

#### Get current user ID and group ID
USER_ID=$(id -u)
GROUP_ID=$(id -g)

#### Cleanup function
cleanup() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}Script failed. Check ${LOG_FILE} for details${NC}"
    fi
}
trap cleanup EXIT

#### Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}    TIG Stack Directory Setup Script      ${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo -e "${YELLOW}Base directory: ${BASE_DIR}${NC}"
echo -e "${YELLOW}User ID: ${USER_ID}${NC}"
echo -e "${YELLOW}Group ID: ${GROUP_ID}${NC}"
echo ""

log_message "Starting TIG stack setup in ${BASE_DIR}"

#################################### Prerequisites Check #########################################################################
check_prerequisites() {
    echo -e "${CYAN}Checking prerequisites...${NC}"
    
    # Check if openssl is available
    if ! command -v openssl &> /dev/null; then
        echo -e "${RED}Error: openssl is required for credential generation${NC}"
        exit 1
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: Docker is not installed${NC}"
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null 2>&1; then
        echo -e "${YELLOW}Warning: Docker daemon may not be running${NC}"
    fi
    
    echo -e "${GREEN}✓ Prerequisites check complete${NC}"
    echo ""
}

#################################### Secure Credential Generation ################################################################
generate_influxdb_token() {
    # Generate cryptographically secure token with sufficient entropy
    # 74 bytes (256 bits) base64 encoded, then prepend with apiv3_
    local random_bytes=$(openssl rand 74 | base64 | tr -d '=+/' | tr -d '\n')
    echo "apiv3_${random_bytes}"
}

generate_grafana_password() {
    # Generate secure password (24 characters with mixed case, numbers, and symbols)
    openssl rand -base64 24 | tr -d '=+/@'
}

load_or_generate_credentials() {
    local creds_file="${BASE_DIR}/.credentials"
    
    if [ -f "$creds_file" ] && [ "$REGENERATE_CREDS" = false ]; then
        echo -e "${CYAN}Loading existing credentials...${NC}"
        source "$creds_file"
        echo -e "${GREEN}✓ Loaded existing credentials${NC}"
    else
        echo -e "${CYAN}Generating secure credentials...${NC}"
        
        INFLUXDB_TOKEN=$(generate_influxdb_token)
        GRAFANA_ADMIN_PASSWORD=$(generate_grafana_password)
        
    # Save credentials securely
    cat > "$creds_file" << EOF
# Generated credentials for TIG stack
# Generated on: $(date)
INFLUXDB_TOKEN="${INFLUXDB_TOKEN}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD}"
EOF
        
        chmod 600 "$creds_file"
        chown "${USER_ID}:${GROUP_ID}" "$creds_file"
        
        echo -e "${GREEN}✓ Generated and saved secure credentials${NC}"
        echo -e "${YELLOW}Credentials saved to: ${creds_file}${NC}"
        echo -e "${YELLOW}InfluxDB Token: ${INFLUXDB_TOKEN:0:20}...${NC}"
        echo -e "${YELLOW}Grafana Password: ${GRAFANA_ADMIN_PASSWORD}${NC}"
    fi
    echo ""
}

#################################### SSL Certificate Generation ##################################################################
#################################### Only required for test domain ###############################################################
generate_ssl_certificates() {
    local cert_dir="${BASE_DIR}/certs"
    local domain="${TLD_DOMAIN}"
    local cert_file="${cert_dir}/${CERT_CRT}"
    local key_file="${cert_dir}/${CERT_KEY}"
    
    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ] || [ "$REGENERATE_CREDS" = true ]; then
        echo -e "${CYAN}Generating SSL certificates for development...${NC}"
        
        # Ensure certs directory exists
        mkdir -p "$cert_dir"
        
        # Generate self-signed certificate with proper extensions
        openssl req -x509 -newkey rsa:4096 \
            -keyout "$key_file" \
            -out "$cert_file" \
            -days 365 -nodes \
            -subj "/C=NL/ST=Gelderland/L=Apeldoorn/O=Development/CN=*.${domain}" \
            -addext "subjectAltName=DNS:*.${domain},DNS:${domain},DNS:${URL_GRAFANA},DNS:${URL_INFLUXDB_EXPLORER}" \
            2>/dev/null
        
        # Set proper ownership first, then permissions
        chown "${USER_ID}:${GROUP_ID}" "$cert_file" "$key_file"
        chmod 644 "$cert_file"
        chmod 600 "$key_file"
        
        echo -e "${GREEN}✓ Generated SSL certificates${NC}"
        echo -e "${YELLOW}Certificate: ${cert_file}${NC}"
        echo -e "${YELLOW}Private Key: ${key_file}${NC}"
    else
        echo -e "${YELLOW}✓ SSL certificates already exist${NC}"
    fi
    echo ""
}

#################################### Functions ###################################################################################
# Function to create directory with proper permissions
create_directory() {
    local dir_path="$1"
    local permissions="$2"
    local description="$3"
    
    echo -e "${CYAN}Creating ${description}...${NC}"
    log_message "Creating directory: ${dir_path}"
    
    if [ ! -d "$dir_path" ]; then
        mkdir -p "$dir_path"
        echo -e "${GREEN}✓ Created directory: ${dir_path}${NC}"
    else
        echo -e "${YELLOW}✓ Directory already exists: ${dir_path}${NC}"
    fi
    
    # Set ownership first, then permissions
    chown "${USER_ID}:${GROUP_ID}" "$dir_path"
    chmod "$permissions" "$dir_path"
    echo -e "${GREEN}✓ Set ownership ${USER_ID}:${GROUP_ID} and permissions ${permissions} on ${dir_path}${NC}"
    echo ""
}

# Function to create file with content
create_file() {
    local file_path="$1"
    local content="$2"
    local permissions="$3"
    local description="$4"
    
    echo -e "${CYAN}Creating ${description}...${NC}"
    log_message "Creating file: ${file_path}"
    
    # Create parent directory if it doesn't exist
    local parent_dir=$(dirname "$file_path")
    if [ ! -d "$parent_dir" ]; then
        mkdir -p "$parent_dir"
        chown "${USER_ID}:${GROUP_ID}" "$parent_dir"
    fi
    
    # Backup existing file if it exists
    if [ -f "$file_path" ]; then
        cp "$file_path" "${file_path}.backup.$(date +%s)"
        echo -e "${YELLOW}✓ Backed up existing file${NC}"
    fi
    
    echo "$content" > "$file_path"
    echo -e "${GREEN}✓ Created file: ${file_path}${NC}"
    
    # Set ownership first, then permissions
    chown "${USER_ID}:${GROUP_ID}" "$file_path"
    chmod "$permissions" "$file_path"
    echo -e "${GREEN}✓ Set ownership ${USER_ID}:${GROUP_ID} and permissions ${permissions} on ${file_path}${NC}"
    echo ""
}

#################################### Configuration Validation ####################################################################
validate_json_config() {
    local json_file="$1"
    if command -v jq &> /dev/null; then
        if ! jq empty "$json_file" 2>/dev/null; then
            echo -e "${RED}Error: Invalid JSON in $json_file${NC}"
            exit 1
        fi
    fi
}

#################################### Main Execution ##############################################################################
#### Execute Script functions
check_prerequisites
load_or_generate_credentials
set_environment_variables
generate_ssl_certificates

####
echo -e "${YELLOW}Starting directory creation...${NC}"
echo ""

# Create main data directories
create_directory "${BASE_DIR}/grafana_data" "755" "Grafana data directory"
create_directory "${BASE_DIR}/influxdb_data" "755" "InfluxDB data directory"
create_directory "${BASE_DIR}/influxdb_data/plugins" "755" "InfluxDB plugins directory"

# Create configuration directories
# Grafana
create_directory "${BASE_DIR}/grafana_config" "755" "Grafana configuration directory"
create_directory "${BASE_DIR}/grafana_provisioning" "755" "Grafana provisioning directory"
create_directory "${BASE_DIR}/grafana_provisioning/dashboards" "755" "Grafana dashboards provisioning directory"
create_directory "${BASE_DIR}/grafana_provisioning/datasources" "755" "Grafana datasources provisioning directory"
# InfluxDB
create_directory "${BASE_DIR}/influxdb/config" "755" "InfluxDB configuration directory"
# Telegraf
create_directory "${BASE_DIR}/telegraf" "755" "Telegraf configuration directory"
# Influx Explorer
create_directory "${BASE_DIR}/influxExplorer/config" "755" "InfluxDB Explorer config directory"
create_directory "${BASE_DIR}/influxExplorer/db" "755" "InfluxDB Explorer database directory"
# nginx
create_directory "${BASE_DIR}/nginx/conf.d" "755" "Nginx configuration directory"
create_directory "${BASE_DIR}/certs" "700" "SSL certificates directory (secure)"
# Scripts
create_directory "${BASE_DIR}/scripts" "755" "Scripts like create-database.sh"

################ Create .env file ################################################################################################
create_file "${BASE_DIR}/.env" "$(cat <<EOF
# TIG Stack Environment Configuration
# Generated on: $(date)
# Author      : Edward Voermans
# Credits     : Suyash Joshi (sjoshi@influxdata.com)
# IMPORTANT: Review and customize these values for your environment

# General
TIMEOUT=${TIMEOUT}
HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL}

# User ID for containers (automatically set)
UID=${USER_ID}

# NGINX Configuration
NGINX_HOST=${NGINX_HOST}
TLD_DOMAIN=${TLD_DOMAIN} 
URL_GRAFANA=${URL_GRAFANA}
URL_INFLUXDB_EXPLORER=${URL_INFLUXDB_EXPLORER}
CERT_CRT=${CERT_CRT}
CERT_KEY=${CERT_KEY}

# InfluxDB Configuration
INFLUXDB_HTTP_PORT=${INFLUXDB_HTTP_PORT}
INFLUXDB_NODE_ID=${INFLUXDB_NODE_ID}
INFLUXDB_HOST=${INFLUXDB_HOST}
INFLUXDB_TOKEN=${INFLUXDB_TOKEN}
INFLUXDB_ORG=${INFLUXDB_ORG}
INFLUXDB_BUCKET=${INFLUXDB_BUCKET}
INFLUXDB_TOKEN_FILE=${INFLUXDB_TOKEN_FILE}

# Grafana Configuration
GRAFANA_HOST=${GRAFANA_HOST}
GRAFANA_PORT=${GRAFANA_PORT}
GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
GRAFANA_SA_NAME=${GRAFANA_SA_NAME}
GRAFANA_TOKEN_NAME=${GRAFANA_TOKEN_NAME}

# Telegraf Configuration
TELEGRAF_HOST=${TELEGRAF_HOST}
TELEGRAF_COLLECTION_INTERVAL=${TELEGRAF_COLLECTION_INTERVAL}

# InfluxDB Explorer Configuration
INFLUXDB_EXPLORER_HOST=${INFLUXDB_EXPLORER_HOST}
INFLUXDB_EXPLORER_PORT=${INFLUXDB_EXPLORER_PORT}
EOF
)" "644" "Environment variables file"

#################################### Create InfluxDB _admin token file ###########################################################
create_file "${BASE_DIR}/influxdb/config/auto-admin-token.json" "$(cat <<EOF
{
  "token": "${INFLUXDB_TOKEN}",
  "name": "_admin",
  "expiry_millis": 3513625132923
}
EOF
)" "600" "Create InfluxDB3 _admin token"

# Validate JSON configuration
validate_json_config "${BASE_DIR}/influxdb/config/auto-admin-token.json"

##################################################################################################################################
#### Scripts #####################################################################################################################
#################################### Create Wrapper Script #######################################################################
create_file "${BASE_DIR}/scripts/wrapper.sh" "$(cat <<EOF
#!/bin/sh
##################################################################################################################################
# Wrapper script to start multiple scripts sequentialy 

set -e
cd /app
echo "Running first script... Create initial InfluxDB Database."
./create-database.sh

echo "Running second script... Create Grafana SA and Token."
./grafana-token.sh

echo "✓ Scripts creation process completed successfully"
EOF
)" "755" "Create Wrapper Script"

#################################### Create Database Script ######################################################################
create_file "${BASE_DIR}/scripts/create-database.sh" "$(cat <<EOF
#!/bin/sh
#### Create Initial Database to accommodate Telegraf sensor data #################################################################

# Function to install required tools
install_required_tools() {
    echo "Checking for required tools..."
    
    # Install required tools (only if not already present)
    if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        echo "Installing required tools..."
        apk add --no-cache curl jq
        
        # Verify installation
        if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
            echo "ERROR: Failed to install required tools"
            return 1
        fi
        echo "Required tools installed successfully"
    else
        echo "Required tools already available"
    fi
    
    return 0
}

# Function to extract and validate token
extract_token() {
    local token_file="\$1"
    
    echo "Extracting authentication token..."
    
    # Check if token file exists
    if [ ! -f "\$token_file" ]; then
        echo "ERROR: Token file not found at \$token_file"
        return 1
    fi
    
    # Extract token using jq
    TOKEN=\$(jq -r '.token' "\$token_file" 2>/dev/null)
    
    if [ -z "\$TOKEN" ] || [ "\$TOKEN" = "null" ]; then
        echo "ERROR: Could not extract valid token from \$token_file"
        echo "File contents (first 100 chars):"
        head -c 100 "\$token_file" 2>/dev/null || echo "Could not read file"
        return 1
    fi
    
    echo "Token extracted successfully"
    echo "Token extracted: \$TOKEN"
    return 0
}

# Function to wait for InfluxDB to be ready
wait_for_influxdb() {
    local host="\$1"
    local port="\$2"
    local timeout="\$3"
    local check_interval="\$4"
    local token="\$5"
    
    echo "Waiting for InfluxDB to be ready..."
    local elapsed=0
    
    while [ \$elapsed -lt \$timeout ]; do
        if curl -sf -H "Authorization: Bearer \$token" "http://\${host}:\${port}/health" >/dev/null 2>&1; then
            echo "InfluxDB is ready! (took \${elapsed}s)"
            return 0
        fi
        
        if [ \$elapsed -ge \$timeout ]; then
            echo "ERROR: InfluxDB failed to become ready within \${timeout} seconds"
            return 1
        fi
        
        echo "InfluxDB not ready yet, waiting... (\${elapsed}s elapsed)"
        sleep \$check_interval
        elapsed=\$((elapsed + check_interval))
    done
    
    return 1
}

# Function to create database
create_database() {
    local host="\$1"
    local port="\$2"
    local database="\$3"
    local token="\$4"
    
    echo "Creating database '\$database'..."
    
    local response=\$(curl -s -w "\\n%{http_code}" \\
        -X POST \\
        -H "Authorization: Token \$token" \\
        -H "Content-Type: application/json" \\
        -d "{\\"db\\": \\"\$database\\"}" \\
        "http://\${host}:\${port}/api/v3/configure/database")
    
    # Parse response
    local http_code=\$(echo "\$response" | tail -n1)
    local response_body=\$(echo "\$response" | sed '\$d')
    
    # Handle different response codes
    case \$http_code in
        200|201)
            echo "✓ Database '\$database' created successfully"
            [ -n "\$response_body" ] && echo "Response: \$response_body"
            return 0
            ;;
        409)
            echo "ℹ Database '\$database' already exists - no action needed"
            return 0
            ;;
        401|403)
            echo "ERROR: Authentication failed. Check token validity."
            return 1
            ;;
        *)
            echo "ERROR: Failed to create database. HTTP Code: \$http_code"
            echo "Response: \$response_body"
            return 1
            ;;
    esac
}

# Function to print startup information
print_startup_info() {
    local host="\$1"
    local port="\$2"
    local database="\$3"
    
    echo "Starting InfluxDB database creation process..."
    echo "Target: \${host}:\${port}"
    echo "Database: \${database}"
}

# Main function to orchestrate the entire process
main() {
    # Print startup information
    print_startup_info "$INFLUXDB_HOST" "$INFLUXDB_HTTP_PORT" "$INFLUXDB_BUCKET"
    
    # Install required tools
    if ! install_required_tools; then
        exit 1
    fi
    
    # Extract authentication token
    if ! extract_token "$INFLUXDB_TOKEN_FILE"; then
        exit 1
    fi
    
    # Wait for InfluxDB to be ready
    if ! wait_for_influxdb "$INFLUXDB_HOST" "$INFLUXDB_HTTP_PORT" "$TIMEOUT" "$HEALTH_CHECK_INTERVAL" "\$TOKEN"; then
        exit 1
    fi
    
    # Create the database
    if ! create_database "$INFLUXDB_HOST" "$INFLUXDB_HTTP_PORT" "$INFLUXDB_BUCKET" "\$TOKEN"; then
        exit 1
    fi
    
    echo "✓ Database creation process completed successfully"
}

# Execute main function if script is run directly (not sourced)
if [ "\${0##*/}" = "create-database.sh" ]; then
    main "\$@"
fi

EOF
)" "755" "Create local_system Database Script"

#################################### Create Grafana SA & Token Script ############################################################
create_file "${BASE_DIR}/scripts/grafana-token.sh" "$(cat <<EOF
#!/bin/sh
#### Create Grafana Service Account and Token ####################################################################################
set -e  # Exit on any error

# Function to install required tools
install_required_tools() {
    echo "Checking for required tools..."
    
    # Install required tools (only if not already present)
    if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        echo "Installing required tools..."
        apk add --no-cache curl jq
        
        # Verify installation
        if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
            echo "ERROR: Failed to install required tools"
            return 1
        fi
        echo "Required tools installed successfully"
    else
        echo "Required tools already available"
    fi
    
    return 0
}

# Function to check if Grafana is healthy
wait_for_grafana() {
    echo "Waiting for Grafana to be healthy at http://${GRAFANA_HOST}:${GRAFANA_PORT}"
    ELAPSED=0

    while [ \$ELAPSED -lt ${TIMEOUT} ]; do
        if curl -sf "http://${GRAFANA_HOST}:${GRAFANA_PORT}/api/health" >/dev/null 2>&1; then
            echo "Grafana is ready! (took \${ELAPSED}s)"
            return 0
        fi

        echo "Grafana not ready yet, waiting... (\${ELAPSED}s elapsed)"
        sleep ${HEALTH_CHECK_INTERVAL}
        ELAPSED=\$((ELAPSED + ${HEALTH_CHECK_INTERVAL}))
    done

    echo "ERROR: Grafana failed to become healthy after ${TIMEOUT} seconds"
    return 1
}

# Function to create Grafana service account
create_grafana_service_account() {
    # Debug: Show what we're sending (redirect to stderr so it doesn't interfere with return value)
    echo "Creating Grafana Service Account..." >&2
    echo "Service Account Name: ${GRAFANA_SA_NAME}" >&2
    echo "Grafana Host: ${GRAFANA_HOST}:${GRAFANA_PORT}" >&2
    echo "Using admin user with password length: \$(echo '${GRAFANA_ADMIN_PASSWORD}' | wc -c)" >&2
    
    # Test authentication first
    echo "Testing authentication..." >&2
    AUTH_TEST=\$(curl -s -w "%{http_code}" -o /dev/null \
        -u admin:${GRAFANA_ADMIN_PASSWORD} \
        http://${GRAFANA_HOST}:${GRAFANA_PORT}/api/org)
    
    if [ "\$AUTH_TEST" != "200" ]; then
        echo "ERROR: Authentication failed (HTTP \$AUTH_TEST)" >&2
        echo "Please check GRAFANA_ADMIN_PASSWORD" >&2
        return 1
    fi
    echo "Authentication successful" >&2

    # Create service account with verbose curl output
    echo "Creating service account..." >&2
    SA_RESPONSE=\$(curl -s -w "HTTP_CODE:%{http_code}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u admin:${GRAFANA_ADMIN_PASSWORD} \
        -X POST \
        --data '{"name":"${GRAFANA_SA_NAME}","role":"Admin","isDisabled":false}' \
        http://${GRAFANA_HOST}:${GRAFANA_PORT}/api/serviceaccounts)

    # Extract HTTP status code and response body
    HTTP_CODE=\$(echo "\$SA_RESPONSE" | grep -o 'HTTP_CODE:[0-9]*' | cut -d: -f2)
    SA_RESPONSE_BODY=\$(echo "\$SA_RESPONSE" | sed 's/HTTP_CODE:[0-9]*\$//')
    
    echo "HTTP Status Code: \$HTTP_CODE" >&2
    echo "SA_Response body: \$SA_RESPONSE_BODY" >&2

    # Check HTTP status code
    if [ "\$HTTP_CODE" != "201" ]; then
        echo "ERROR: Service account creation failed with HTTP \$HTTP_CODE" >&2
        echo "Response: \$SA_RESPONSE_BODY" >&2
        return 1
    fi

    SA_ID=\$(echo "\$SA_RESPONSE_BODY" | jq -r .id)

    # Check if we got a valid ID
    if [ "\$SA_ID" = "null" ] || [ -z "\$SA_ID" ]; then
        echo "ERROR: Failed to get service account ID" >&2
        echo "Response: \$SA_RESPONSE_BODY" >&2
        return 1
    fi

    echo "Created service account with ID: \$SA_ID" >&2
    
    # Return ONLY the service account ID to stdout
    echo "\$SA_ID"
    return 0
}

# Function to store token securely with metadata
store_grafana_token() {
    TOKEN="\$1"
    SA_ID="\$2"
    
    if [ -z "\$TOKEN" ]; then
        echo "ERROR: Token is required for storage"
        return 1
    fi
    
    # Generate timestamp
    TIMESTAMP=\$(date '+%Y-%m-%d %H:%M:%S UTC')
    
    # Create token file with metadata
    cat > /app/grafana_SA_Token << EOL
# Grafana API Token Information
# Generated: \$TIMESTAMP
# Service Account ID: \${SA_ID:-"N/A"}
# Service Account Name: ${GRAFANA_SA_NAME}
# Token Name: ${GRAFANA_TOKEN_NAME}
# Grafana Host: ${GRAFANA_HOST}:${GRAFANA_PORT}

GRAFANA_API_TOKEN=\$TOKEN
EOL
    
    # Set secure permissions
    chmod 644 /app/grafana_SA_Token
    echo "Token stored securely in /app/grafana_SA_Token with metadata"
    
    return 0
}

# Function to create API token for service account
create_grafana_api_token() {
    SA_ID="\$1"
    
    if [ -z "\$SA_ID" ]; then
        echo "ERROR: Service Account ID is required"
        return 1
    fi
    
    echo "Creating API token for service account ID: \$SA_ID"

    # Create token
    echo "Creating API token..."
    TOKEN_RESPONSE=\$(curl -s -w "HTTP_CODE:%{http_code}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u admin:${GRAFANA_ADMIN_PASSWORD} \
        -X POST \
        --data '{"name":"${GRAFANA_TOKEN_NAME}"}' \
        http://${GRAFANA_HOST}:${GRAFANA_PORT}/api/serviceaccounts/\$SA_ID/tokens)

    # Extract HTTP status code and response body
    TOKEN_HTTP_CODE=\$(echo "\$TOKEN_RESPONSE" | grep -o 'HTTP_CODE:[0-9]*' | cut -d: -f2)
    TOKEN_RESPONSE_BODY=\$(echo "\$TOKEN_RESPONSE" | sed 's/HTTP_CODE:[0-9]*\$//')
    
    echo "Token HTTP Status Code: \$TOKEN_HTTP_CODE"
    echo "Token_Response body: \$TOKEN_RESPONSE_BODY"

    # Check if token creation was successful
    if [ "\$TOKEN_HTTP_CODE" != "200" ]; then
        echo "ERROR: Token creation failed with HTTP \$TOKEN_HTTP_CODE"
        echo "Response: \$TOKEN_RESPONSE_BODY"
        return 1
    fi

    TOKEN=\$(echo "\$TOKEN_RESPONSE_BODY" | jq -r .key)

    # Check if we got a valid token
    if [ "\$TOKEN" = "null" ] || [ -z "\$TOKEN" ]; then
        echo "ERROR: Failed to get API token"
        echo "Response: \$TOKEN_RESPONSE_BODY"
        return 1
    fi

    echo "Grafana API token created successfully"
    
    # Store token in environment variable
    export GRAFANA_API_TOKEN="\$TOKEN"

    # Store token securely with metadata
    if ! store_grafana_token "\$TOKEN" "\$SA_ID"; then
        echo "WARNING: Failed to store token to file, but token is available in GRAFANA_API_TOKEN variable"
        return 1
    fi

    return 0
}

# Updated main function that calls all functions in sequence
main() {
    echo "Starting Grafana token creation process..."

    # Step 0: Install required tools
    echo "Step 0: Checking and installing required tools..."
    if ! install_required_tools; then
        echo "Failed to install required tools"
        exit 1
    fi

    # Validate required environment variables
    if [ -z "${GRAFANA_ADMIN_PASSWORD}" ] || [ "${GRAFANA_ADMIN_PASSWORD}" = "admin" ]; then
        echo "Using default admin password. Consider setting GRAFANA_ADMIN_PASSWORD."
    fi

    # Step 1: Wait for Grafana to be ready
    echo "Step 1: Waiting for Grafana to be ready..."
    if ! wait_for_grafana; then
        exit 1
    fi

    # Step 2: Create the service account and capture the ID
    echo "Step 2: Creating service account..."
    SA_ID=\$(create_grafana_service_account)
    SA_CREATE_RESULT=\$?
    
    if [ \$SA_CREATE_RESULT -ne 0 ]; then
        echo "Service account creation failed"
        exit 1
    fi

    # Step 3: Create the API token using the service account ID
    echo "Step 3: Creating API token..."
    if create_grafana_api_token "\$SA_ID"; then
        echo "Token creation completed successfully!"
        exit 0
    else
        echo "Token creation failed"
        exit 1
    fi
}
main
#### End ####

EOF
)" "755" "Create Grafana SA & Token Script"

##################################################################################################################################
#################################### Create Config Files #########################################################################

# [The rest of your configuration files would go here - telegraf.conf, grafana.ini, nginx configs, etc.]

################ Create basic telegraf.conf ################
create_file "${BASE_DIR}/telegraf/telegraf.conf" "$(cat <<EOF
# Telegraf Configuration for TIG Stack
# Generated on: $(date)
# Security: This configuration uses secure token-based authentication

[agent]
  interval = "${TELEGRAF_COLLECTION_INTERVAL}"
  flush_interval = "${TELEGRAF_COLLECTION_INTERVAL}"
  hostname = "${TELEGRAF_HOST}"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_jitter = "0s"
  precision = ""
  debug = false
  quiet = false
  logfile = ""
  omit_hostname = false

[[inputs.cpu]]
  percpu = true
  totalcpu = true
  collect_cpu_time = false
  report_active = true

[[inputs.mem]]

[[inputs.disk]]
  mount_points = ["/"]
  ignore_fs = ["tmpfs", "devtmpfs", "devfs", "iso9660", "overlay", "aufs", "squashfs"]

[[inputs.diskio]]
  devices = ["sda", "sdb", "nvme0n1"]
  skip_serial_number = true

[[inputs.net]]
  interfaces = ["eth*", "en*"]
  ignore_protocol_stats = false

[[inputs.system]]

[[outputs.influxdb_v2]]
  urls = ["http://${INFLUXDB_HOST}:${INFLUXDB_HTTP_PORT}"]
  token = "${INFLUXDB_TOKEN}"
  organization = "${INFLUXDB_ORG}"
  bucket = "${INFLUXDB_BUCKET}"
  timeout = "5s"
  user_agent = "telegraf"
  content_encoding = "gzip"
EOF
)" "644" "Telegraf configuration"

################ Create basic grafana.ini configuration ##########################################################################
create_file "${BASE_DIR}/grafana_config/grafana.ini" "$(cat <<EOF
# Grafana Configuration for TIG Stack
# Generated on: $(date)
# Security: Uses secure passwords and proper domain configuration

[server]
protocol = http
http_port = ${GRAFANA_PORT}
domain = ${TLD_DOMAIN}
enforce_domain = false
root_url = %(protocol)s://%(domain)s:%(http_port)s/
serve_from_sub_path = false
static_root_path = public
enable_gzip = false
cert_file = 
cert_key = 
socket = 
router_logging = false

[security]
admin_user = ${GRAFANA_ADMIN_USER}
admin_password = ${GRAFANA_ADMIN_PASSWORD}
secret_key = SW2YcwTIb9zpOOhoPsMm
login_remember_days = 7
cookie_username = grafana_user
cookie_remember_name = grafana_remember
disable_gravatar = false
data_source_proxy_whitelist = 
disable_brute_force_login_protection = false
cookie_secure = false
cookie_samesite = lax
allow_embedding = false
strict_transport_security = false
strict_transport_security_max_age_seconds = 86400
strict_transport_security_preload = false
strict_transport_security_subdomains = false
x_content_type_options = true
x_xss_protection = true

[users]
allow_sign_up = false
allow_org_create = false
auto_assign_org = true
auto_assign_org_id = 1
auto_assign_org_role = Viewer
verify_email_enabled = false
login_hint = email or username
password_hint = password
default_theme = dark
external_manage_link_url = 
external_manage_link_name = 
external_manage_info = 

[auth.anonymous]
enabled = false
org_name = Main Org.
org_role = Viewer
hide_version = false

[auth.basic]
enabled = true

[auth.proxy]
enabled = false

[log]
mode = console
level = warn
filters = 
format = console

[log.console]
level = 
format = console

[log.file]
level = 
format = text
log_rotate = true
max_lines = 1000000
max_size_shift = 28
daily_rotate = true
max_days = 7

[analytics]
reporting_enabled = false
check_for_updates = false
google_analytics_ua_id = 
google_tag_manager_id = 

[security]
disable_initial_admin_creation = false
admin_user = ${GRAFANA_ADMIN_USER}
admin_password = ${GRAFANA_ADMIN_PASSWORD}

[snapshots]
external_enabled = false

[dashboards]
versions_to_keep = 20

[unified_alerting]
enabled = true
execute_alerts = true
error_or_timeout = alerting
nodata_or_nullvalues = no_data
concurrent_render_limit = 5

[explore]
enabled = true

[unified_alerting]
enabled = false

EOF
)" "644" "Grafana configuration"

################ Create Grafana dashboard provisioning configuration #############################################################
create_file "${BASE_DIR}/grafana_provisioning/dashboards/dashboards.yaml" "$(cat <<EOF
# Grafana Dashboard Provisioning Configuration
# Generated on: $(date)
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF
)" "644" "Grafana dashboard provisioning"

################ Create Grafana datasource provisioning configuration ############################################################
create_file "${BASE_DIR}/grafana_provisioning/datasources/influxdb.yaml" "$(cat <<EOF
# Grafana Datasource Provisioning Configuration  
# Generated on: $(date)
# Security: Uses secure token-based authentication for InfluxDB
apiVersion: 1

deleteDatasources:
  - name: InfluxDB
    orgId: 1

datasources:
  - name: ${INFLUXDB_HOST}
    type: influxdb
    access: proxy
    orgId: 1
    url: http://${INFLUXDB_HOST}:${INFLUXDB_HTTP_PORT}
    password: 
    user: 
    database: 
    basicAuth: false
    basicAuthUser: 
    basicAuthPassword: 
    withCredentials: false
    isDefault: true
    jsonData:
      dbName: ${INFLUXDB_BUCKET}
      httpHeaderName1: Bearer
      httpMode: GET
      insecureGrpc: true      
      version: SQL
      organization: ${INFLUXDB_ORG}
      defaultBucket: ${INFLUXDB_BUCKET}
      tlsSkipVerify: true
    secureJsonData:
      token: ${INFLUXDB_TOKEN}
    version: 1
    editable: true
EOF
)" "644" "Grafana InfluxDB datasource provisioning"

################ Create nginx main configuration #################################################################################
create_file "${BASE_DIR}/nginx/nginx.conf" "$(cat <<EOF
# Nginx Main Configuration for TIG Stack
# Generated on: $(date)
# Security: Configured with modern security headers and SSL settings

user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Security basics
    server_tokens off;
    
    # Simple logging
    log_format main '\$remote_addr - \$remote_user [\$time_local] \"\$request\" '
                    '\$status \$body_bytes_sent \"\$http_referer\" '
                    '\"\$http_user_agent\" \"\$http_x_forwarded_for\"';
    
    # Performance essentials
    sendfile on;
    keepalive_timeout 65;
    client_max_body_size 100M;
    
    # Security timeouts and limits
    client_body_timeout 10s;
    client_header_timeout 10s;
    client_body_buffer_size 1M;
    
    # Essential rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone \$binary_remote_addr zone=login:10m rate=1r/s;
    limit_req_zone \$binary_remote_addr zone=general:10m rate=10r/s;    

    # Modern SSL only
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    
    # WebSocket support
    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        ''      close;
    }
    
    # Gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
    
    # Include site configs
    include /etc/nginx/conf.d/*.conf;
}
EOF
)" "644" "Nginx main configuration"

################ Create nginx default server configuration #######################################################################
create_file "${BASE_DIR}/nginx/conf.d/default.conf" "$(cat <<EOF
# Nginx Default Server Configuration for TIG Stack
# Generated on: $(date)
# Security: Implements comprehensive security headers and modern SSL practices

################ SECURITY: CATCH UNKNOWN HOSTS ################
server {
    listen 80 default_server;
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate /etc/nginx/certs/${CERT_CRT};
    ssl_certificate_key /etc/nginx/certs/${CERT_KEY};
    return 444;
}

################ HTTP TO HTTPS REDIRECT ################
server {
    listen 80;
    server_name ${URL_GRAFANA} ${URL_INFLUXDB_EXPLORER};
    return 301 https://$server_name$request_uri;
}

################ GRAFANA SERVER ################
server {
    listen 443 ssl;
    http2 on; # Enable HTTP/2 for better performance 
    server_name ${URL_GRAFANA};
    
    # SSL
    ssl_certificate /etc/nginx/certs/${CERT_CRT};
    ssl_certificate_key /etc/nginx/certs/${CERT_KEY};
    
    # Security headers:
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Block sensitive files
    location ~ /\.|~$|\.(sql|bak|backup|log)$ {
        deny all;
        return 404;
    }
    
    # Health check
    location /nginx-health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Main proxy
    location / {
        limit_req zone=general burst=20 nodelay;
        # limit_conn conn_limit 10;
        client_max_body_size 50M;
        
        proxy_pass http://${GRAFANA_HOST}:${GRAFANA_PORT};
        include /etc/nginx/proxy_params;
    }
}

################ INFLUXDB EXPLORER SERVER ################
server {
    listen 443 ssl;
    http2 on; # Enable HTTP/2 for better performance 
    server_name ${URL_INFLUXDB_EXPLORER};
    
    # SSL
    ssl_certificate /etc/nginx/certs/${CERT_CRT};
    ssl_certificate_key /etc/nginx/certs/${CERT_KEY};
    
    # Same security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Block sensitive files
    location ~ /\.|~$|\.(sql|bak|backup|log)$ {
        deny all;
        return 404;
    }
    
    # Health check
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # API with higher limits
    location /api/ {
        limit_req zone=api burst=50 nodelay;
        proxy_pass http://${INFLUXDB_EXPLORER_HOST}:${INFLUXDB_EXPLORER_PORT};
        include /etc/nginx/proxy_params;
        
        # Database operation timeouts
        # proxy_connect_timeout 90s;
        # proxy_send_timeout 120s;
        # proxy_read_timeout 120s;
    }
    
    # Main proxy
    location / {
        limit_req zone=general burst=30 nodelay;
        # limit_conn conn_limit 15;
        client_max_body_size 100M;
        
        proxy_pass http://${INFLUXDB_EXPLORER_HOST}:${INFLUXDB_EXPLORER_PORT};
        include /etc/nginx/proxy_params;
    }
}
EOF
)" "644" "Nginx default server configuration"

################ Create nginx proxy parameters ###################################################################################
create_file "${BASE_DIR}/nginx/proxy_params" "$(cat <<EOF
# Nginx Proxy Parameters for TIG Stack
# Generated on: $(date)
# Security: Secure proxy headers configuration

# Essential proxy headers
proxy_set_header Host \$host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto \$scheme;

# WebSocket support
proxy_http_version 1.1;
proxy_set_header Upgrade \$http_upgrade;
proxy_set_header Connection \$connection_upgrade;

# Security
proxy_hide_header X-Powered-By;

# Reasonable timeouts
proxy_connect_timeout 60s;
proxy_send_timeout 60s;
proxy_read_timeout 60s;
EOF
)" "644" "Nginx proxy parameters"

################ Create InfluxDB Explorer configuration ################
create_file "${BASE_DIR}/influxExplorer/config/config.json" "$(cat <<EOF
{
  "DEFAULT_INFLUX_SERVER": "http://${INFLUXDB_HOST}:${INFLUXDB_HTTP_PORT}",
  "DEFAULT_INFLUX_DATABASE": "${INFLUXDB_BUCKET}",
  "DEFAULT_API_TOKEN": "${INFLUXDB_TOKEN}",
  "DEFAULT_SERVER_NAME": "${INFLUXDB_HOST}"
}
EOF
)" "644" "InfluxDB Explorer configuration"

# Validate InfluxDB Explorer JSON configuration
validate_json_config "${BASE_DIR}/influxExplorer/config/config.json"

################ Create a comprehensive README for certificates ##################################################################
create_file "${BASE_DIR}/certs/README.md" "$(cat <<'EOF'
# SSL Certificates Directory

This directory contains SSL certificates for the TIG Stack development environment.

## Auto-Generated Certificates

The setup script automatically generates self-signed certificates suitable for development use:

- `eddysys.nl.crt` - SSL certificate (world-readable, 644 permissions)
- `eddysys.nl.key` - Private key (owner-only readable, 600 permissions)

## Certificate Details

- **Algorithm**: RSA 4096-bit
- **Validity**: 365 days from generation
- **Subject**: CN=*.eddysys.nl
- **SAN (Subject Alternative Names)**:
  - DNS:*.eddysys.nl
  - DNS:eddysys.nl
  - DNS:tig-grafana.eddysys.nl
  - DNS:tig-explorer.eddysys.nl

## Security Notes

### Development Environment
- These are **self-signed certificates** for development only
- Browsers will show security warnings - this is expected
- **DO NOT use these certificates in production**

### Production Environment
For production use, replace with certificates from a trusted CA:

1. Obtain certificates from a Certificate Authority (Let's Encrypt, etc.)
2. Replace the .crt and .key files
3. Ensure proper file permissions:
   ```bash
   chmod 644 *.crt
   chmod 600 *.key
   chown root:root *
   ```

## Manual Certificate Generation

If you need to regenerate certificates manually:

```bash
# Generate new self-signed certificate
openssl req -x509 -newkey rsa:4096 \\
    -keyout eddysys.nl.key \\
    -out eddysys.nl.crt \\
    -days 365 -nodes \\
    -subj "/C=NL/ST=Gelderland/L=Apeldoorn/O=Development/CN=*.eddysys.nl" \\
    -addext "subjectAltName=DNS:*.eddysys.nl,DNS:eddysys.nl,DNS:tig-grafana.eddysys.nl,DNS:tig-explorer.eddysys.nl"

# Set proper permissions
chmod 644 eddysys.nl.crt
chmod 600 eddysys.nl.key
```

## Trusting Self-Signed Certificates

### Browser Trust
To avoid browser warnings during development:

1. **Chrome/Edge**: Go to chrome://settings/certificates → Import → Trust for websites
2. **Firefox**: Go to about:preferences#privacy → View Certificates → Import
3. **Safari**: Double-click certificate → Add to Keychain → Trust

### System Trust (Linux)
```bash
# Copy certificate to system trust store
sudo cp eddysys.nl.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

## Troubleshooting

### Certificate Errors
- **"Certificate not trusted"**: Expected for self-signed certs
- **"Certificate name mismatch"**: Check your hosts file includes the domains
- **"Certificate expired"**: Regenerate with `--regenerate-creds` flag

### File Permission Issues
```bash
# Fix certificate permissions
chmod 644 eddysys.nl.crt
chmod 600 eddysys.nl.key
chown $(id -u):$(id -g) eddysys.nl.*
```

## Hosts File Configuration

Add these entries to your `/etc/hosts` file for local development:

```
127.0.0.1    eddysys.nl
127.0.0.1    tig-grafana.eddysys.nl
127.0.0.1    tig-explorer.eddysys.nl
```

## Security Best Practices

1. **Never commit private keys** to version control
2. **Use strong passwords** for certificate stores
3. **Rotate certificates regularly** in production
4. **Monitor certificate expiration** dates
5. **Use HTTPS everywhere** - even in development

---

*Generated by TIG Stack Setup Script*
*For questions: edward@voermans.com*
EOF
)" "644" "Certificate directory comprehensive README"

################ Create Grafana system monitoring dashboard JSON #################################################################
create_file "${BASE_DIR}/grafana_provisioning/dashboards/system-monitoring.json" "$(cat <<'EOF'
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": {
          "type": "grafana",
          "uid": "-- Grafana --"
        },
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Annotations & Alerts",
        "type": "dashboard"
      }
    ]
  },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 0,
  "id": 1,
  "links": [],
  "panels": [
    {
      "datasource": {
        "type": "influxdb",
        "uid": "P1E71DEBAF15C8614"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "axisBorderShow": false,
            "axisCenteredZero": false,
            "axisColorMode": "text",
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "barWidthFactor": 0.6,
            "drawStyle": "line",
            "fillOpacity": 0,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "insertNulls": false,
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "auto",
            "spanNulls": false,
            "stacking": {
              "group": "A",
              "mode": "none"
            },
            "thresholdsStyle": {
              "mode": "off"
            }
          },
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": 0
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          }
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 0,
        "y": 0
      },
      "id": 1,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom",
          "showLegend": true
        },
        "tooltip": {
          "hideZeros": false,
          "mode": "single",
          "sort": "none"
        }
      },
      "pluginVersion": "12.1.1",
      "targets": [
        {
          "dataset": "iox",
          "datasource": {
            "type": "influxdb",
            "uid": "P1E71DEBAF15C8614"
          },
          "editorMode": "code",
          "format": "table",
          "rawQuery": true,
          "rawSql": "SELECT \"cpu\", \"usage_user\", \"time\" FROM \"cpu\" WHERE \"time\" >= $__timeFrom AND \"time\" <= $__timeTo AND \"cpu\" = 'cpu0'",
          "refId": "A",
          "sql": {
            "columns": [
              {
                "parameters": [],
                "type": "function"
              }
            ],
            "groupBy": [
              {
                "property": {
                  "type": "string"
                },
                "type": "groupBy"
              }
            ]
          }
        },
        {
          "dataset": "iox",
          "datasource": {
            "type": "influxdb",
            "uid": "P1E71DEBAF15C8614"
          },
          "editorMode": "code",
          "format": "table",
          "hide": false,
          "rawQuery": true,
          "rawSql": "SELECT \"cpu\", \"usage_user\", \"time\" FROM \"cpu\" WHERE \"time\" >= $__timeFrom AND \"time\" <= $__timeTo AND \"cpu\" = 'cpu1'",
          "refId": "B",
          "sql": {
            "columns": [
              {
                "parameters": [],
                "type": "function"
              }
            ],
            "groupBy": [
              {
                "property": {
                  "type": "string"
                },
                "type": "groupBy"
              }
            ]
          }
        },
        {
          "dataset": "iox",
          "datasource": {
            "type": "influxdb",
            "uid": "P1E71DEBAF15C8614"
          },
          "editorMode": "code",
          "format": "table",
          "hide": false,
          "rawQuery": true,
          "rawSql": "SELECT \"cpu\", \"usage_user\", \"time\" FROM \"cpu\" WHERE \"time\" >= $__timeFrom AND \"time\" <= $__timeTo AND \"cpu\" = 'cpu2'",
          "refId": "C",
          "sql": {
            "columns": [
              {
                "parameters": [],
                "type": "function"
              }
            ],
            "groupBy": [
              {
                "property": {
                  "type": "string"
                },
                "type": "groupBy"
              }
            ]
          }
        }
      ],
      "title": "CPU",
      "type": "timeseries"
    }
  ],
  "preload": false,
  "schemaVersion": 41,
  "tags": [],
  "templating": {
    "list": []
  },
  "time": {
    "from": "now-1h",
    "to": "now"
  },
  "timepicker": {},
  "timezone": "browser",
  "title": "TIG-Stack using InfluxDB3",
  "uid": "b8099355-ee76-46b4-8fde-c7ccf83c93b9",
  "version": 3
}
EOF
)" "644" "Grafana System Monitoring Dashboard"

#################################### Final Steps #################################################################################
log_message "TIG stack setup completed successfully"

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}    Directory Setup Complete!             ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "${CYAN}1.${NC} Review the .env file and customize values if needed"
echo -e "${CYAN}2.${NC} SSL certificates have been generated automatically"
echo -e "${CYAN}3.${NC} Review configuration files in their respective directories"
echo -e "${CYAN}4.${NC} Run: ${GREEN}docker compose up -d${NC}"
echo -e "${CYAN}5.${NC} Access services at:"
echo -e "   • Grafana: https://${URL_GRAFANA}"
echo -e "   • InfluxDB Explorer: https://${URL_INFLUXDB_EXPLORER}"
echo ""
echo -e "${YELLOW}Generated files:${NC}"
echo -e "  • .env (environment variables)"
echo -e "  • .credentials (secure credential storage)"
echo -e "  • SSL certificates in certs/"
echo -e "  • Configuration files for all services"
echo ""
echo -e "${YELLOW}Security Notes:${NC}"
echo -e "  • Credentials are stored securely in .credentials file"
echo -e "  • SSL certificates are self-signed for development"
echo -e "  • Use --regenerate-creds to generate new credentials"
echo ""
echo -e "${GREEN}Setup completed successfully!${NC}"
echo -e "${YELLOW}Setup log available at: ${LOG_FILE}${NC}"

##################################################################################################################################