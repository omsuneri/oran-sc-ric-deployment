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

info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1"
}

display_banner() {
    echo "=================================================="
    echo "   Near-RT RIC Platform Deployment Suite"
    echo "   O-RAN Software Community"
    echo "=================================================="
}

check_system_requirements() {
    log "Checking system requirements..."
    
    if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        warn "This deployment is optimized for Ubuntu. Other distributions may require modifications."
    fi
    
    MEMORY_GB=$(free -g | awk 'NR==2{print $2}')
    if [ "$MEMORY_GB" -lt 8 ]; then
        warn "Recommended minimum 8GB RAM. Current: ${MEMORY_GB}GB"
    fi
    
    DISK_GB=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
    if [ "$DISK_GB" -lt 50 ]; then
        warn "Recommended minimum 50GB free space. Current: ${DISK_GB}GB"
    fi
    
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -lt 4 ]; then
        warn "Recommended minimum 4 CPU cores. Current: ${CPU_CORES}"
    fi
    
    log "System requirements check completed"
    log "CPU: ${CPU_CORES} cores, Memory: ${MEMORY_GB}GB, Disk: ${DISK_GB}GB free"
}

# Make scripts executable
prepare_scripts() {
    log "Preparing deployment scripts..."
    
    chmod +x deployment/scripts/deploy_ric.sh
    chmod +x deployment/scripts/deploy_xapp.sh
    chmod +x deployment/scripts/deploy_e2sim.sh
    
    log "Scripts prepared successfully"
}

# Deploy RIC platform
deploy_ric_platform() {
    log "Starting RIC Platform Deployment..."
    info "This process may take 15-30 minutes depending on your internet connection"
    
    cd deployment/scripts
    ./deploy_ric.sh
    cd ../..
    
    log "RIC Platform deployment completed"
}

# Deploy xApp
deploy_xapp() {
    log "Starting xApp Deployment..."
    info "Deploying sample xApp for demonstration"
    
    cd deployment/scripts
    ./deploy_xapp.sh
    cd ../..
    
    log "xApp deployment completed"
}

# Deploy E2 simulator
deploy_e2_simulator() {
    log "Starting E2 Simulator Deployment (Bonus Component)..."
    info "This component provides E2 interface simulation capabilities"
    
    cd deployment/scripts
    ./deploy_e2sim.sh
    cd ../..
    
    log "E2 Simulator deployment completed"
}

# Generate deployment summary
generate_summary() {
    log "Generating deployment summary..."
    
    # Create summary file
    cat > deployment/logs/deployment_summary.txt << EOF
Near-RT RIC Platform Deployment Summary
======================================
Deployment Date: $(date)
Deployment Duration: ${deployment_duration} seconds

Component Status:
================
EOF

    if kubectl get pods -n ricplt &>/dev/null; then
        echo "RIC Platform: DEPLOYED" >> deployment/logs/deployment_summary.txt
        RUNNING_PODS=$(kubectl get pods -n ricplt --no-headers | grep Running | wc -l)
        TOTAL_PODS=$(kubectl get pods -n ricplt --no-headers | wc -l)
        echo "   Pods Running: $RUNNING_PODS/$TOTAL_PODS" >> deployment/logs/deployment_summary.txt
    else
        echo "RIC Platform: FAILED" >> deployment/logs/deployment_summary.txt
    fi
    
    if kubectl get pods -n ricxapp &>/dev/null; then
        echo "xApp: DEPLOYED" >> deployment/logs/deployment_summary.txt
        XAPP_PODS=$(kubectl get pods -n ricxapp --no-headers | grep Running | wc -l)
        echo "   xApp Pods Running: $XAPP_PODS" >> deployment/logs/deployment_summary.txt
    else
        echo "xApp: FAILED" >> deployment/logs/deployment_summary.txt
    fi
    
    if kubectl get pods -n ricplt -l app=e2sim &>/dev/null; then
        echo "E2 Simulator: DEPLOYED" >> deployment/logs/deployment_summary.txt
    else
        echo "E2 Simulator: FAILED" >> deployment/logs/deployment_summary.txt
    fi
    
    # Add resource information
    echo "" >> deployment/logs/deployment_summary.txt
    echo "Resource Usage:" >> deployment/logs/deployment_summary.txt
    echo "===============" >> deployment/logs/deployment_summary.txt
    kubectl top nodes >> deployment/logs/deployment_summary.txt 2>/dev/null || echo "Resource metrics not available" >> deployment/logs/deployment_summary.txt
    
    # Add service endpoints
    echo "" >> deployment/logs/deployment_summary.txt
    echo "Service Endpoints:" >> deployment/logs/deployment_summary.txt
    echo "==================" >> deployment/logs/deployment_summary.txt
    kubectl get svc -n ricplt >> deployment/logs/deployment_summary.txt 2>/dev/null || echo "Services not available" >> deployment/logs/deployment_summary.txt
    
    log "Deployment summary generated: deployment/logs/deployment_summary.txt"
}

# Final verification
final_verification() {
    log "Performing final verification..."
    
    # Test API endpoints
    info "Testing API endpoints..."
    
    # Get node IP and app manager port
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    APPMGR_PORT=$(kubectl get svc -n ricplt -o jsonpath='{.items[?(@.metadata.name=="service-ricplt-appmgr-http")].spec.ports[0].nodePort}')
    
    if [ -n "$NODE_IP" ] && [ -n "$APPMGR_PORT" ]; then
        log "Application Manager endpoint: http://$NODE_IP:$APPMGR_PORT"
        
        # Test health endpoint
        if curl -s -o /dev/null -w "%{http_code}" http://$NODE_IP:$APPMGR_PORT/appmgr/ric/v1/health/ready | grep -q "200"; then
            log "Application Manager health check: PASSED"
        else
            warn "Application Manager health check: FAILED"
        fi
    else
        warn "Could not determine Application Manager endpoint"
    fi
    
    # Display final status
    echo ""
    log "=== Final Deployment Status ==="
    kubectl get pods -A | grep -E "(ricplt|ricinfra|ricxapp)"
    echo ""
    
    log "Verification completed"
}

# Display next steps
display_next_steps() {
    echo ""
    info "=== Deployment Completed Successfully ==="
    echo ""
    echo "Documentation Generated:"
    echo "   Deployment Report: docs/deployment-report.md"
    echo "   Troubleshooting Guide: troubleshooting/issues.md"
    echo "   Deployment Logs: deployment/logs/"
    echo ""
    echo "Useful Commands:"
    echo "   Check pod status: kubectl get pods -A"
    echo "   View RIC pods: kubectl get pods -n ricplt"
    echo "   View xApp pods: kubectl get pods -n ricxapp"
    echo "   View services: kubectl get svc -n ricplt"
    echo "   Check logs: kubectl logs <pod-name> -n <namespace>"
    echo ""
    echo "Access Points:"
    if [ -n "$NODE_IP" ] && [ -n "$APPMGR_PORT" ]; then
        echo "   Application Manager: http://$NODE_IP:$APPMGR_PORT"
        echo "   Health Check: http://$NODE_IP:$APPMGR_PORT/appmgr/ric/v1/health/ready"
    fi
    echo ""
    echo "Next Steps:"
    echo "   1. Review deployment logs for any issues"
    echo "   2. Test xApp functionality"
    echo "   3. Explore E2 simulator integration"
    echo "   4. Submit documentation to: srao@linuxfoundation.org"
    echo ""
    warn "Remember to backup your deployment configuration!"
}

# Cleanup function
cleanup() {
    if [ $? -ne 0 ]; then
        error "Deployment failed. Check logs in deployment/logs/ for details"
        echo ""
        echo "🔧 Troubleshooting Steps:"
        echo "   1. Check system requirements"
        echo "   2. Review troubleshooting/issues.md"
        echo "   3. Check individual component logs"
        echo "   4. Ensure all prerequisites are installed"
    fi
}

# Interactive menu
show_menu() {
    echo ""
    echo "Select deployment components:"
    echo "1) Full deployment (RIC + xApp + E2 Simulator)"
    echo "2) RIC Platform only"
    echo "3) RIC Platform + xApp"
    echo "4) Custom component selection"
    echo "5) Status check only"
    echo "q) Quit"
    echo -n "Enter your choice [1-5,q]: "
}

# Custom component selection
custom_selection() {
    echo ""
    echo "Select components to deploy:"
    
    read -p "Deploy RIC Platform? [Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        DEPLOY_RIC=true
    else
        DEPLOY_RIC=false
    fi
    
    read -p "Deploy xApp? [Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        DEPLOY_XAPP=true
    else
        DEPLOY_XAPP=false
    fi
    
    read -p "Deploy E2 Simulator? [Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        DEPLOY_E2SIM=true
    else
        DEPLOY_E2SIM=false
    fi
}

# Status check function
status_check() {
    log "Checking deployment status..."
    
    echo ""
    echo "=== Kubernetes Cluster Status ==="
    kubectl get nodes
    
    echo ""
    echo "=== RIC Platform Pods ==="
    kubectl get pods -n ricplt 2>/dev/null || echo "RIC platform not deployed"
    
    echo ""
    echo "=== xApp Pods ==="
    kubectl get pods -n ricxapp 2>/dev/null || echo "xApp not deployed"
    
    echo ""
    echo "=== Services ==="
    kubectl get svc -n ricplt 2>/dev/null || echo "RIC services not available"
    
    echo ""
    echo "=== Helm Releases ==="
    helm list -A 2>/dev/null || echo "Helm releases not available"
}

# Main function
main() {
    # Record start time
    START_TIME=$(date +%s)
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    # Display banner
    display_banner
    
    # Check system requirements
    check_system_requirements
    
    # Prepare scripts
    prepare_scripts
    
    # Interactive mode or direct execution
    if [ "$1" == "--interactive" ] || [ "$1" == "-i" ]; then
        while true; do
            show_menu
            read -r choice
            case $choice in
                1)
                    DEPLOY_RIC=true
                    DEPLOY_XAPP=true
                    DEPLOY_E2SIM=true
                    break
                    ;;
                2)
                    DEPLOY_RIC=true
                    DEPLOY_XAPP=false
                    DEPLOY_E2SIM=false
                    break
                    ;;
                3)
                    DEPLOY_RIC=true
                    DEPLOY_XAPP=true
                    DEPLOY_E2SIM=false
                    break
                    ;;
                4)
                    custom_selection
                    break
                    ;;
                5)
                    status_check
                    exit 0
                    ;;
                q|Q)
                    log "Deployment cancelled by user"
                    exit 0
                    ;;
                *)
                    error "Invalid option. Please try again."
                    ;;
            esac
        done
    else
        # Default: full deployment
        DEPLOY_RIC=true
        DEPLOY_XAPP=true
        DEPLOY_E2SIM=true
    fi
    
    # Execute deployment based on selection
    if [ "$DEPLOY_RIC" = true ]; then
        deploy_ric_platform
    fi
    
    if [ "$DEPLOY_XAPP" = true ]; then
        deploy_xapp
    fi
    
    if [ "$DEPLOY_E2SIM" = true ]; then
        deploy_e2_simulator
    fi
    
    # Calculate deployment duration
    END_TIME=$(date +%s)
    deployment_duration=$((END_TIME - START_TIME))
    
    # Generate summary and verify
    generate_summary
    final_verification
    display_next_steps
    
    log "Total deployment time: ${deployment_duration} seconds"
    log "Deployment process completed successfully!"
}

# Handle script arguments
case "$1" in
    --help|-h)
        echo "Near-RT RIC Platform Deployment Script"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  -i, --interactive    Interactive component selection"
        echo "  --status            Check deployment status only"
        echo "  -h, --help          Show this help message"
        echo ""
        echo "Default: Full deployment (RIC + xApp + E2 Simulator)"
        exit 0
        ;;
    --status)
        status_check
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
