#!/bin/bash

set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1"
}

setup_helm_repo() {
    log "Setting up local Helm repository..."
    
    mkdir -p charts
    
    log "Starting chartmuseum container..."
    docker run --rm -d --name chartmuseum \
        -p 8090:8080 \
        -e DEBUG=1 \
        -e STORAGE=local \
        -e STORAGE_LOCAL_ROOTDIR=/charts \
        -v $(pwd)/charts:/charts \
        chartmuseum/chartmuseum:latest
    
    export CHART_REPO_URL=http://0.0.0.0:8090
    
    sleep 10
    
    log "Chartmuseum is running on port 8090"
}

# Install dms_cli tool
install_dms_cli() {
    log "Installing dms_cli tool..."
    
    # Clone appmgr repository
    if [ ! -d "appmgr" ]; then
        git clone "https://gerrit.o-ran-sc.org/r/ric-plt/appmgr"
    fi
    
    # Install Python3 and pip if not available
    if ! command -v pip3 &> /dev/null; then
        log "Installing Python3 and pip..."
        sudo apt update
        sudo apt install -y python3-pip
    fi
    
    # Install dms_cli
    cd appmgr/xapp_orchestrater/dev/xapp_onboarder
    pip3 install ./ 2>&1 | tee ../../../../xapps/logs/dms_cli_install.log
    cd ../../../../
    
    # Set permissions for non-root users
    sudo chmod 755 /usr/local/bin/dms_cli 2>/dev/null || true
    sudo chmod -R 755 /usr/local/lib/python3* 2>/dev/null || true
    
    log "dms_cli installation completed"
}

# Create sample xApp configuration
create_sample_xapp_config() {
    log "Creating sample xApp configuration..."
    
    # Create sample config file
    cat > xapps/configs/sample_xapp_config.json << 'EOF'
{
    "xapp_name": "sample-xapp",
    "version": "1.0.0",
    "containers": [
        {
            "name": "sample-xapp",
            "image": {
                "registry": "docker.io",
                "name": "o-ran-sc/ric-app-ts",
                "tag": "1.0.0"
            },
            "ports": [
                {
                    "name": "http",
                    "container": 8080,
                    "protocol": "TCP"
                }
            ]
        }
    ],
    "messaging": {
        "ports": [
            {
                "name": "rmr-data",
                "container": 4560,
                "protocol": "TCP"
            },
            {
                "name": "rmr-route",
                "container": 4561,
                "protocol": "TCP"
            }
        ]
    },
    "controls": {
        "logging": {
            "level": "info"
        }
    }
}
EOF

    # Create sample schema file
    cat > xapps/configs/sample_xapp_schema.json << 'EOF'
{
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "properties": {
        "xapp_name": {
            "type": "string"
        },
        "version": {
            "type": "string"
        },
        "containers": {
            "type": "array"
        }
    },
    "required": ["xapp_name", "version"]
}
EOF

    log "Sample xApp configuration created"
}

# Onboard xApp
onboard_xapp() {
    log "Onboarding sample xApp..."
    
    # Create logs directory
    mkdir -p xapps/logs
    
    # Onboard the xApp
    dms_cli onboard xapps/configs/sample_xapp_config.json xapps/configs/sample_xapp_schema.json 2>&1 | tee xapps/logs/xapp_onboard.log
    
    log "xApp onboarding completed"
}

# List available charts
list_charts() {
    log "Listing available charts in repository..."
    
    curl -X GET http://localhost:8090/api/charts | jq . 2>&1 | tee xapps/logs/available_charts.log || warn "Could not list charts (jq may not be installed)"
}

# Deploy xApp
deploy_xapp() {
    local xapp_name="sample-xapp"
    local version="1.0.0"
    local namespace="ricxapp"
    
    log "Deploying xApp: $xapp_name"
    
    # Install the xApp
    dms_cli install $xapp_name $version $namespace 2>&1 | tee xapps/logs/xapp_deploy.log
    
    # Wait for xApp to be ready
    log "Waiting for xApp to be ready..."
    kubectl wait --for=condition=Ready pods -l app=$xapp_name -n $namespace --timeout=300s || warn "xApp may not be ready yet"
    
    # Check xApp status
    log "xApp deployment status:"
    kubectl get pods -n $namespace | tee xapps/logs/xapp_pods.log
    kubectl get svc -n $namespace | tee xapps/logs/xapp_services.log
}

# Health check for xApp
xapp_health_check() {
    local xapp_name="sample-xapp"
    local namespace="ricxapp"
    
    log "Performing xApp health check..."
    
    dms_cli health_check $xapp_name $namespace 2>&1 | tee xapps/logs/xapp_health.log || warn "Health check may have failed"
}

# Cleanup function
cleanup() {
    log "Cleaning up..."
    docker stop chartmuseum 2>/dev/null || true
    docker rm chartmuseum 2>/dev/null || true
}

# Main function
main() {
    log "Starting xApp Deployment Process"
    log "================================"
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    # Create logs directory
    mkdir -p xapps/logs
    
    # Check if RIC platform is running
    if ! kubectl get pods -n ricplt &>/dev/null; then
        error "RIC platform is not deployed. Please deploy RIC platform first."
        exit 1
    fi
    
    # Run deployment steps
    setup_helm_repo
    install_dms_cli
    create_sample_xapp_config
    onboard_xapp
    list_charts
    deploy_xapp
    xapp_health_check
    
    log "xApp deployment process completed!"
    log "Check the logs in xapps/logs/ for detailed information"
}

# Run main function
main "$@"
