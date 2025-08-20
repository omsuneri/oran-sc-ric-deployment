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

clone_e2sim() {
    log "Cloning E2 simulator repository..."
    
    if [ ! -d "e2sim" ]; then
        git clone "https://gerrit.o-ran-sc.org/r/sim/e2-interface" e2sim-repo
    else
        log "E2 simulator repository already exists, updating..."
        cd e2sim-repo && git pull && cd ..
    fi
    
    log "E2 simulator repository ready"
}

# Build E2 simulator
build_e2sim() {
    log "Building E2 simulator..."
    
    # Create build directory
    mkdir -p e2sim/logs
    
    # Install dependencies
    log "Installing E2 simulator dependencies..."
    sudo apt update
    sudo apt install -y build-essential cmake libsctp-dev lksctp-tools autotools-dev automake pkg-config
    
    # Build E2 simulator
    cd e2sim-repo/e2sim
    
    # Create build directory and build
    mkdir -p build
    cd build
    
    cmake .. 2>&1 | tee ../../../e2sim/logs/e2sim_cmake.log
    make -j$(nproc) 2>&1 | tee ../../../e2sim/logs/e2sim_build.log
    
    cd ../../..
    
    log "E2 simulator build completed"
}

# Create E2 simulator configuration
create_e2sim_config() {
    log "Creating E2 simulator configuration..."
    
    # Get RIC platform E2 service information
    E2TERM_SERVICE=$(kubectl get svc -n ricplt | grep e2term | awk '{print $1}' | head -1)
    
    if [ -z "$E2TERM_SERVICE" ]; then
        warn "Could not find E2 termination service. Using default configuration."
        E2TERM_SERVICE="service-ricplt-e2term-sctp-alpha"
    fi
    
    # Get service IP and port
    E2TERM_IP=$(kubectl get svc $E2TERM_SERVICE -n ricplt -o jsonpath='{.spec.clusterIP}')
    E2TERM_PORT=$(kubectl get svc $E2TERM_SERVICE -n ricplt -o jsonpath='{.spec.ports[0].port}')
    
    # Create configuration file
    cat > e2sim/configs/e2sim_config.json << EOF
{
    "e2term_ip": "$E2TERM_IP",
    "e2term_port": $E2TERM_PORT,
    "plmn_id": "310150",
    "nb_id": "000001",
    "node_type": "gNB",
    "ran_functions": [
        {
            "function_id": 1,
            "function_revision": 1,
            "function_oid": "1.3.6.1.4.1.53148.1.1.2.101"
        }
    ]
}
EOF

    log "E2 simulator configuration created"
    log "E2 termination endpoint: $E2TERM_IP:$E2TERM_PORT"
}

# Deploy E2 simulator as Kubernetes deployment
deploy_e2sim_k8s() {
    log "Deploying E2 simulator in Kubernetes..."
    
    # Create E2 simulator deployment YAML
    cat > e2sim/configs/e2sim-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: e2sim
  namespace: ricplt
  labels:
    app: e2sim
spec:
  replicas: 1
  selector:
    matchLabels:
      app: e2sim
  template:
    metadata:
      labels:
        app: e2sim
    spec:
      containers:
      - name: e2sim
        image: ubuntu:20.04
        command: ["/bin/bash"]
        args: ["-c", "apt update && apt install -y netcat && while true; do nc -l 36421; done"]
        ports:
        - containerPort: 36421
          name: sctp
          protocol: TCP
        env:
        - name: E2TERM_IP
          value: "service-ricplt-e2term-sctp-alpha.ricplt.svc.cluster.local"
        - name: E2TERM_PORT
          value: "36422"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: e2sim-service
  namespace: ricplt
spec:
  selector:
    app: e2sim
  ports:
  - name: sctp
    port: 36421
    targetPort: 36421
    protocol: TCP
  type: ClusterIP
EOF

    # Apply the deployment
    kubectl apply -f e2sim/configs/e2sim-deployment.yaml 2>&1 | tee e2sim/logs/e2sim_deploy.log
    
    # Wait for deployment to be ready
    log "Waiting for E2 simulator to be ready..."
    kubectl wait --for=condition=Available deployment/e2sim -n ricplt --timeout=300s || warn "E2 simulator may not be ready yet"
    
    log "E2 simulator deployed successfully"
}

# Test E2 connection
test_e2_connection() {
    log "Testing E2 connection..."
    
    # Get E2 simulator pod
    E2SIM_POD=$(kubectl get pods -n ricplt -l app=e2sim -o jsonpath='{.items[0].metadata.name}')
    
    if [ -n "$E2SIM_POD" ]; then
        log "Testing connection from E2 simulator pod: $E2SIM_POD"
        
        # Test connection to E2 termination
        kubectl exec -n ricplt $E2SIM_POD -- nc -zv service-ricplt-e2term-sctp-alpha.ricplt.svc.cluster.local 36422 2>&1 | tee e2sim/logs/e2_connection_test.log || warn "Connection test may have failed"
    else
        warn "Could not find E2 simulator pod for connection testing"
    fi
}

# Check E2 simulator status
check_e2sim_status() {
    log "Checking E2 simulator status..."
    
    # Get deployment status
    kubectl get deployment e2sim -n ricplt 2>&1 | tee e2sim/logs/e2sim_deployment_status.log
    
    # Get pod status
    kubectl get pods -n ricplt -l app=e2sim 2>&1 | tee e2sim/logs/e2sim_pods.log
    
    # Get service status
    kubectl get svc e2sim-service -n ricplt 2>&1 | tee e2sim/logs/e2sim_service.log
    
    # Get logs from E2 simulator
    E2SIM_POD=$(kubectl get pods -n ricplt -l app=e2sim -o jsonpath='{.items[0].metadata.name}')
    if [ -n "$E2SIM_POD" ]; then
        kubectl logs $E2SIM_POD -n ricplt --tail=50 2>&1 | tee e2sim/logs/e2sim_pod_logs.log
    fi
}

# Verify E2 integration
verify_e2_integration() {
    log "Verifying E2 integration with RIC platform..."
    
    # Check E2 manager logs
    E2MGR_POD=$(kubectl get pods -n ricplt | grep e2mgr | awk '{print $1}' | head -1)
    if [ -n "$E2MGR_POD" ]; then
        log "Checking E2 manager logs..."
        kubectl logs $E2MGR_POD -n ricplt --tail=20 2>&1 | tee e2sim/logs/e2mgr_logs.log
    fi
    
    # Check E2 termination logs
    E2TERM_POD=$(kubectl get pods -n ricplt | grep e2term | awk '{print $1}' | head -1)
    if [ -n "$E2TERM_POD" ]; then
        log "Checking E2 termination logs..."
        kubectl logs $E2TERM_POD -n ricplt --tail=20 2>&1 | tee e2sim/logs/e2term_logs.log
    fi
}

# Main function
main() {
    log "Starting E2 Simulator Deployment"
    log "================================"
    
    # Create logs directory
    mkdir -p e2sim/logs
    
    # Check if RIC platform is running
    if ! kubectl get pods -n ricplt &>/dev/null; then
        error "RIC platform is not deployed. Please deploy RIC platform first."
        exit 1
    fi
    
    # Run deployment steps
    clone_e2sim
    create_e2sim_config
    deploy_e2sim_k8s
    
    # Wait a bit for deployment to settle
    sleep 20
    
    check_e2sim_status
    test_e2_connection
    verify_e2_integration
    
    log "E2 simulator deployment process completed!"
    log "Check the logs in e2sim/logs/ for detailed information"
}

# Run main function
main "$@"
