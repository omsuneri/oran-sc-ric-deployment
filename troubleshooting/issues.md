# Troubleshooting Guide - Near-RT RIC Deployment

This document contains common issues encountered during Near-RT RIC platform deployment and their solutions.

## Table of Contents
1. [Prerequisites Issues](#prerequisites-issues)
2. [Infrastructure Setup Issues](#infrastructure-setup-issues)
3. [RIC Platform Deployment Issues](#ric-platform-deployment-issues)
4. [xApp Deployment Issues](#xapp-deployment-issues)
5. [E2 Simulator Issues](#e2-simulator-issues)
6. [General Debugging](#general-debugging)

## Prerequisites Issues

### Issue: Docker Installation Conflicts
**Symptoms:**
- Kubernetes pods fail to start
- Docker daemon errors
- Network connectivity issues

**Diagnosis:**
```bash
sudo systemctl status docker
docker --version
kubectl get nodes
```

**Solution:**
```bash
# Remove existing Docker installation
sudo apt remove docker docker-engine docker.io containerd runc
sudo apt autoremove
sudo rm -rf /var/lib/docker

# Use RIC deployment script for clean installation
cd ric-dep/bin
sudo ./install_k8s_and_helm.sh
```

### Issue: Insufficient System Resources
**Symptoms:**
- Pods stuck in Pending state
- OutOfMemory errors
- Slow deployment

**Diagnosis:**
```bash
kubectl describe nodes
kubectl top nodes
free -h
df -h
```

**Solution:**
- Minimum 4 CPU cores, 8GB RAM required
- Free up disk space (minimum 50GB)
- Close unnecessary applications

## Infrastructure Setup Issues

### Issue: Kubernetes Cluster Not Ready
**Symptoms:**
- `kubectl get nodes` shows NotReady
- Pods fail to schedule
- DNS resolution issues

**Diagnosis:**
```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system
journalctl -u kubelet -n 50
```

**Solution:**
```bash
# Reset and reinitialize cluster
sudo kubeadm reset
sudo systemctl restart kubelet
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Configure kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install CNI plugin
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```

### Issue: Helm Installation Problems
**Symptoms:**
- `helm version` fails
- Chart installation errors
- Template rendering issues

**Diagnosis:**
```bash
helm version
helm repo list
which helm
```

**Solution:**
```bash
# Remove existing Helm
sudo rm -f /usr/local/bin/helm

# Install Helm 3
curl https://get.helm.sh/helm-v3.12.0-linux-amd64.tar.gz | tar xz
sudo mv linux-amd64/helm /usr/local/bin/helm
helm version
```

## RIC Platform Deployment Issues

### Issue: Recipe Configuration Errors
**Symptoms:**
- Deployment script fails with YAML errors
- Services not accessible
- IP address configuration issues

**Diagnosis:**
```bash
cd ric-dep/bin
./install -f ../RECIPE_EXAMPLE/PLATFORM/example_recipe_latest_stable.yaml --dry-run
```

**Solution:**
```bash
# Get correct node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Update recipe file
sed -i "s/ricip: \"\"/ricip: \"$NODE_IP\"/" deployment/recipes/deployment_recipe.yaml
sed -i "s/auxip: \"\"/auxip: \"$NODE_IP\"/" deployment/recipes/deployment_recipe.yaml
```

### Issue: Chart Installation Timeouts
**Symptoms:**
- Helm install hangs
- Pods stuck in ContainerCreating
- Image pull errors

**Diagnosis:**
```bash
helm list -A
kubectl get pods -n ricplt
kubectl describe pod <pod-name> -n ricplt
```

**Solution:**
```bash
# Check image availability
docker pull nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-appmgr:4.0.6

# Increase timeout
helm install --timeout 20m0s <release-name> <chart>

# Check network connectivity
kubectl run test-pod --image=busybox --rm -it -- nslookup kubernetes.default
```

### Issue: Namespace Creation Failures
**Symptoms:**
- Namespaces not created
- RBAC errors
- Permission denied

**Diagnosis:**
```bash
kubectl get namespaces
kubectl auth can-i create namespaces
```

**Solution:**
```bash
# Create namespaces manually if needed
kubectl create namespace ricplt
kubectl create namespace ricinfra
kubectl create namespace ricxapp

# Check cluster admin permissions
kubectl cluster-info
```

## xApp Deployment Issues

### Issue: DMS CLI Installation Fails
**Symptoms:**
- `pip3 install` errors
- Missing Python dependencies
- Permission errors

**Diagnosis:**
```bash
python3 --version
pip3 --version
which dms_cli
```

**Solution:**
```bash
# Install Python and pip
sudo apt update
sudo apt install -y python3 python3-pip python3-dev

# Install with user flag
pip3 install --user ./

# Add to PATH
echo 'export PATH=$PATH:$HOME/.local/bin' >> ~/.bashrc
source ~/.bashrc

# Fix permissions
sudo chmod 755 /usr/local/bin/dms_cli
```

### Issue: ChartMuseum Connection Problems
**Symptoms:**
- Cannot connect to chart repository
- Port already in use
- Docker container fails to start

**Diagnosis:**
```bash
docker ps | grep chartmuseum
netstat -tulpn | grep 8090
curl http://localhost:8090/health
```

**Solution:**
```bash
# Stop existing container
docker stop chartmuseum
docker rm chartmuseum

# Use different port if needed
docker run --rm -d --name chartmuseum \
    -p 8091:8080 \
    -e DEBUG=1 \
    -e STORAGE=local \
    -e STORAGE_LOCAL_ROOTDIR=/charts \
    -v $(pwd)/charts:/charts \
    chartmuseum/chartmuseum:latest

# Update environment variable
export CHART_REPO_URL=http://0.0.0.0:8091
```

### Issue: xApp Onboarding Failures
**Symptoms:**
- Config file validation errors
- Schema validation failures
- Chart generation errors

**Diagnosis:**
```bash
dms_cli onboard --help
cat xapps/configs/sample_xapp_config.json | jq .
```

**Solution:**
```bash
# Validate JSON syntax
cat xapps/configs/sample_xapp_config.json | python3 -m json.tool

# Fix common config issues
# Ensure all required fields are present
# Check image registry accessibility
# Verify port configurations

# Test with minimal config
cat > minimal_config.json << 'EOF'
{
    "xapp_name": "test-xapp",
    "version": "1.0.0",
    "containers": [{
        "name": "test-xapp",
        "image": {
            "registry": "docker.io",
            "name": "hello-world",
            "tag": "latest"
        }
    }]
}
EOF
```

## E2 Simulator Issues

### Issue: Build Dependencies Missing
**Symptoms:**
- CMake configuration fails
- Compilation errors
- Library not found errors

**Diagnosis:**
```bash
cmake --version
gcc --version
pkg-config --list-all | grep sctp
```

**Solution:**
```bash
# Install build essentials
sudo apt update
sudo apt install -y build-essential cmake autotools-dev automake pkg-config

# Install SCTP libraries
sudo apt install -y libsctp-dev lksctp-tools

# Install additional dependencies
sudo apt install -y libasn1c-dev libcurl4-openssl-dev
```

### Issue: E2 Connection Problems
**Symptoms:**
- Cannot connect to E2 termination
- SCTP connection failures
- Network unreachable errors

**Diagnosis:**
```bash
kubectl get svc -n ricplt | grep e2term
kubectl get endpoints -n ricplt
kubectl exec -n ricplt <e2sim-pod> -- netstat -tulpn
```

**Solution:**
```bash
# Check E2 termination service
kubectl describe svc service-ricplt-e2term-sctp-alpha -n ricplt

# Test connectivity from within cluster
kubectl run test-pod --image=busybox --rm -it -- nc -zv service-ricplt-e2term-sctp-alpha.ricplt.svc.cluster.local 36422

# Check firewall rules
sudo iptables -L
sudo ufw status
```

## General Debugging

### Useful Commands for Debugging

#### Pod Information
```bash
# Get all pods across namespaces
kubectl get pods -A

# Describe pod with detailed events
kubectl describe pod <pod-name> -n <namespace>

# Get pod logs
kubectl logs <pod-name> -n <namespace>

# Follow logs in real-time
kubectl logs -f <pod-name> -n <namespace>

# Get previous container logs
kubectl logs <pod-name> -n <namespace> --previous
```

#### Service Information
```bash
# Get all services
kubectl get svc -A

# Test service connectivity
kubectl run test-pod --image=busybox --rm -it -- nslookup <service-name>.<namespace>.svc.cluster.local

# Port forward for testing
kubectl port-forward svc/<service-name> 8080:80 -n <namespace>
```

#### Resource Usage
```bash
# Node resource usage
kubectl top nodes

# Pod resource usage
kubectl top pods -A

# Describe node resources
kubectl describe nodes
```

#### Events and Troubleshooting
```bash
# Get cluster events
kubectl get events -A --sort-by='.lastTimestamp'

# Get events for specific namespace
kubectl get events -n ricplt --sort-by='.lastTimestamp'

# Check cluster info
kubectl cluster-info
kubectl cluster-info dump
```

### Log Analysis

#### Common Error Patterns
1. **ImagePullBackOff**: Check image name, tag, and registry access
2. **CrashLoopBackOff**: Check application logs and configuration
3. **Pending**: Check resource constraints and node capacity
4. **ContainerCreating**: Check volume mounts and secrets

#### Log Locations
- **RIC Deployment Logs**: `deployment/logs/`
- **xApp Logs**: `xapps/logs/`
- **E2 Simulator Logs**: `e2sim/logs/`
- **Kubernetes Logs**: `/var/log/containers/`

### Performance Optimization

#### Resource Limits
```yaml
resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "128Mi"
    cpu: "100m"
```

#### Node Optimization
```bash
# Increase inotify limits
echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Optimize networking
echo 'net.core.somaxconn = 32768' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.ip_local_port_range = 1024 65000' | sudo tee -a /etc/sysctl.conf
```

## Emergency Recovery Procedures

### Complete Reset
```bash
# Stop all services
sudo systemctl stop kubelet
sudo systemctl stop docker

# Reset Kubernetes
sudo kubeadm reset -f

# Clean up
sudo rm -rf ~/.kube/
sudo rm -rf /etc/kubernetes/
sudo rm -rf /var/lib/etcd/

# Restart services
sudo systemctl start docker
sudo systemctl start kubelet

# Reinitialize
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
```

### Partial Recovery
```bash
# Restart specific deployments
kubectl rollout restart deployment <deployment-name> -n <namespace>

# Delete and recreate problematic pods
kubectl delete pod <pod-name> -n <namespace>

# Update deployments
kubectl patch deployment <deployment-name> -n <namespace> -p '{"spec":{"template":{"metadata":{"annotations":{"date":"'$(date)'"}}}}}'
```

## Contact and Support

For additional support:
- **O-RAN SC Documentation**: https://docs.o-ran-sc.org/
- **O-RAN SC Wiki**: https://lf-o-ran-sc.atlassian.net/wiki/
- **Community Forums**: https://lists.o-ran-sc.org/
- **Issue Tracking**: https://jira.o-ran-sc.org/

---

**Last Updated:** August 20, 2025  
**Version:** 1.0
