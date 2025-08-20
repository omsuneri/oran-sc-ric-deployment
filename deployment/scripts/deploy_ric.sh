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

check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! grep -q "Ubuntu 20.04" /etc/os-release 2>/dev/null; then
        warn "This script is designed for Ubuntu 20.04. Current OS may not be fully supported."
    fi
    
    local missing_tools=()
    
    if ! command -v git &> /dev/null; then
        missing_tools+=("git")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi
    
    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        error "Missing required tools: ${missing_tools[*]}"
        log "Please install missing tools before proceeding"
        return 1
    fi
    
    log "Prerequisites check completed successfully"
}

install_infrastructure() {
    log "Installing Kubernetes, Helm, and Docker infrastructure..."
    
    if [ ! -d "ric-dep" ]; then
        log "Cloning RIC deployment repository..."
        git clone "https://gerrit.o-ran-sc.org/r/ric-plt/ric-dep"
    else
        log "RIC deployment repository already exists, updating..."
        cd ric-dep && git pull && cd ..
    fi
    
    # Install infrastructure
    log "Installing Kubernetes, Helm, and Docker..."
    cd ric-dep/bin
    chmod +x install_k8s_and_helm.sh
    sudo ./install_k8s_and_helm.sh
    cd ../..
    
    log "Infrastructure installation completed"
}

# Install common templates
install_common_templates() {
    log "Installing common templates to Helm..."
    
    cd ric-dep/bin
    chmod +x install_common_templates_to_helm.sh
    ./install_common_templates_to_helm.sh
    cd ../..
    
    log "Common templates installation completed"
}

# Configure deployment recipe
configure_recipe() {
    log "Configuring deployment recipe..."
    
    # Copy the example recipe
    cp ric-dep/RECIPE_EXAMPLE/PLATFORM/example_recipe_latest_stable.yaml deployment/recipes/deployment_recipe.yaml
    
    # Get node IP for configuration
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    
    # Update the recipe with node IP
    sed -i "s/ricip: \"\"/ricip: \"$NODE_IP\"/" deployment/recipes/deployment_recipe.yaml
    sed -i "s/auxip: \"\"/auxip: \"$NODE_IP\"/" deployment/recipes/deployment_recipe.yaml
    
    log "Deployment recipe configured with IP: $NODE_IP"
}

# Deploy Near-RT RIC platform
deploy_ric_platform() {
    log "Deploying Near-RT RIC platform..."
    
    cd ric-dep/bin
    chmod +x install
    ./install -f ../../deployment/recipes/deployment_recipe.yaml 2>&1 | tee ../../deployment/logs/ric_deployment.log
    cd ../..
    
    log "Near-RT RIC platform deployment initiated"
}

# Check deployment status
check_deployment_status() {
    log "Checking deployment status..."
    
    # Wait for pods to be ready
    log "Waiting for pods to be ready (this may take several minutes)..."
    kubectl wait --for=condition=Ready pods --all -n ricplt --timeout=600s || warn "Some pods may not be ready yet"
    
    # Get helm releases
    log "Helm releases:"
    helm list -A | tee deployment/logs/helm_releases.log
    
    # Get pods status
    log "Pod status in ricplt namespace:"
    kubectl get pods -n ricplt | tee deployment/logs/ricplt_pods.log
    
    log "Pod status in ricinfra namespace:"
    kubectl get pods -n ricinfra | tee deployment/logs/ricinfra_pods.log
    
    # Get services
    log "Services in ricplt namespace:"
    kubectl get svc -n ricplt | tee deployment/logs/ricplt_services.log
    
    log "Services in ricinfra namespace:"
    kubectl get svc -n ricinfra | tee deployment/logs/ricinfra_services.log
}

# Health check
health_check() {
    log "Performing health check..."
    
    # Get ingress controller port
    APPMGR_PORT=$(kubectl get svc -n ricplt -o jsonpath='{.items[?(@.metadata.name=="service-ricplt-appmgr-http")].spec.ports[0].nodePort}')
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    
    if [ -n "$APPMGR_PORT" ] && [ -n "$NODE_IP" ]; then
        log "Testing application manager health endpoint..."
        curl -v http://$NODE_IP:$APPMGR_PORT/appmgr/ric/v1/health/ready 2>&1 | tee deployment/logs/health_check.log || warn "Health check failed"
    else
        warn "Could not determine application manager endpoint for health check"
    fi
}

# Main deployment function
main() {
    log "Starting Near-RT RIC Platform Deployment"
    log "========================================="
    
    # Create logs directory
    mkdir -p deployment/logs
    
    # Run deployment steps
    if check_prerequisites; then
        install_infrastructure
        install_common_templates
        configure_recipe
        deploy_ric_platform
        
        # Wait a bit for deployment to settle
        sleep 30
        
        check_deployment_status
        health_check
        
        log "Deployment process completed!"
        log "Check the logs in deployment/logs/ for detailed information"
        log "Next steps: Deploy xApp using the xapp deployment script"
    else
        error "Prerequisites check failed. Please resolve issues before proceeding."
        exit 1
    fi
}

# Run main function
main "$@"
