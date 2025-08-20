#!/bin/bash

echo "================================="
echo " Near-RT RIC Deployment Status "
echo "================================="
echo ""

if ! command -v kubectl &> /dev/null; then
    echo "kubectl not found. Kubernetes may not be installed."
    exit 1
fi

echo "Kubernetes Cluster Status:"
if kubectl cluster-info &> /dev/null; then
    echo "Cluster is running"
    kubectl get nodes --no-headers | while read line; do
        NODE_NAME=$(echo $line | awk '{print $1}')
        NODE_STATUS=$(echo $line | awk '{print $2}')
        echo "   Node $NODE_NAME: $NODE_STATUS"
    done
else
    echo "Cluster is not accessible"
    exit 1
fi

echo ""

echo "RIC Platform Status (ricplt namespace):"
if kubectl get namespace ricplt &> /dev/null; then
    TOTAL_PODS=$(kubectl get pods -n ricplt --no-headers 2>/dev/null | wc -l)
    RUNNING_PODS=$(kubectl get pods -n ricplt --no-headers 2>/dev/null | grep Running | wc -l)
    READY_PODS=$(kubectl get pods -n ricplt --no-headers 2>/dev/null | awk '$2~/1\/1|2\/2/ {print $1}' | wc -l)
    
    if [ $TOTAL_PODS -gt 0 ]; then
        echo -e "   ${GREEN}✅ Namespace exists${NC}"
        echo -e "   📊 Pods: $RUNNING_PODS/$TOTAL_PODS running, $READY_PODS ready"
        
        if [ $RUNNING_PODS -eq $TOTAL_PODS ] && [ $READY_PODS -eq $TOTAL_PODS ]; then
            echo -e "   ${GREEN}✅ All RIC components are healthy${NC}"
        else
            echo -e "   ${YELLOW}⚠️  Some RIC components may have issues${NC}"
            kubectl get pods -n ricplt --no-headers | grep -v Running | head -5
        fi
    else
        echo -e "   ${RED}❌ No pods found in ricplt namespace${NC}"
    fi
else
    echo -e "   ${RED}❌ RIC Platform not deployed (ricplt namespace not found)${NC}"
fi

echo ""

# Check RIC Infrastructure
echo -e "${BLUE}🏭 RIC Infrastructure Status (ricinfra namespace):${NC}"
if kubectl get namespace ricinfra &> /dev/null; then
    INFRA_PODS=$(kubectl get pods -n ricinfra --no-headers 2>/dev/null | wc -l)
    INFRA_RUNNING=$(kubectl get pods -n ricinfra --no-headers 2>/dev/null | grep Running | wc -l)
    
    if [ $INFRA_PODS -gt 0 ]; then
        echo -e "   ${GREEN}✅ Infrastructure namespace exists${NC}"
        echo -e "   📊 Pods: $INFRA_RUNNING/$INFRA_PODS running"
    else
        echo -e "   ${YELLOW}⚠️  No infrastructure pods found${NC}"
    fi
else
    echo -e "   ${RED}❌ RIC Infrastructure not deployed${NC}"
fi

echo ""

# Check xApps
echo -e "${BLUE}📱 xApp Status (ricxapp namespace):${NC}"
if kubectl get namespace ricxapp &> /dev/null; then
    XAPP_PODS=$(kubectl get pods -n ricxapp --no-headers 2>/dev/null | wc -l)
    XAPP_RUNNING=$(kubectl get pods -n ricxapp --no-headers 2>/dev/null | grep Running | wc -l)
    
    if [ $XAPP_PODS -gt 0 ]; then
        echo -e "   ${GREEN}✅ xApp namespace exists${NC}"
        echo -e "   📊 xApp Pods: $XAPP_RUNNING/$XAPP_PODS running"
        kubectl get pods -n ricxapp --no-headers | while read line; do
            POD_NAME=$(echo $line | awk '{print $1}')
            POD_STATUS=$(echo $line | awk '{print $3}')
            if [ "$POD_STATUS" = "Running" ]; then
                echo -e "   ${GREEN}✅ $POD_NAME: $POD_STATUS${NC}"
            else
                echo -e "   ${RED}❌ $POD_NAME: $POD_STATUS${NC}"
            fi
        done
    else
        echo -e "   ${YELLOW}⚠️  No xApps deployed${NC}"
    fi
else
    echo -e "   ${RED}❌ xApp namespace not found${NC}"
fi

echo ""

# Check E2 Simulator
echo -e "${BLUE}🔌 E2 Simulator Status:${NC}"
E2SIM_PODS=$(kubectl get pods -n ricplt -l app=e2sim --no-headers 2>/dev/null | wc -l)
if [ $E2SIM_PODS -gt 0 ]; then
    E2SIM_RUNNING=$(kubectl get pods -n ricplt -l app=e2sim --no-headers 2>/dev/null | grep Running | wc -l)
    echo -e "   ${GREEN}✅ E2 Simulator deployed${NC}"
    echo -e "   📊 E2 Simulator Pods: $E2SIM_RUNNING/$E2SIM_PODS running"
else
    echo -e "   ${YELLOW}⚠️  E2 Simulator not deployed${NC}"
fi

echo ""

# Check Helm releases
echo -e "${BLUE}📦 Helm Releases:${NC}"
if command -v helm &> /dev/null; then
    HELM_RELEASES=$(helm list -A --no-headers 2>/dev/null | wc -l)
    if [ $HELM_RELEASES -gt 0 ]; then
        echo -e "   ${GREEN}✅ Found $HELM_RELEASES Helm releases${NC}"
        helm list -A --no-headers 2>/dev/null | head -10 | while read line; do
            RELEASE_NAME=$(echo $line | awk '{print $1}')
            RELEASE_STATUS=$(echo $line | awk '{print $8}')
            if [ "$RELEASE_STATUS" = "deployed" ]; then
                echo -e "   ${GREEN}✅ $RELEASE_NAME: $RELEASE_STATUS${NC}"
            else
                echo -e "   ${RED}❌ $RELEASE_NAME: $RELEASE_STATUS${NC}"
            fi
        done
    else
        echo -e "   ${YELLOW}⚠️  No Helm releases found${NC}"
    fi
else
    echo -e "   ${RED}❌ Helm not found${NC}"
fi

echo ""

# Check key services
echo -e "${BLUE}🌐 Key Services:${NC}"
if kubectl get svc -n ricplt service-ricplt-appmgr-http &>/dev/null; then
    APPMGR_PORT=$(kubectl get svc service-ricplt-appmgr-http -n ricplt -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    echo -e "   ${GREEN}✅ Application Manager: http://$NODE_IP:$APPMGR_PORT${NC}"
else
    echo -e "   ${RED}❌ Application Manager service not found${NC}"
fi

if kubectl get svc -n ricplt service-ricplt-e2term-sctp-alpha &>/dev/null; then
    echo -e "   ${GREEN}✅ E2 Termination service available${NC}"
else
    echo -e "   ${RED}❌ E2 Termination service not found${NC}"
fi

echo ""

# Overall status summary
echo -e "${BLUE}📋 Overall Status Summary:${NC}"
if kubectl get pods -n ricplt &>/dev/null && [ $RUNNING_PODS -gt 0 ]; then
    if [ $RUNNING_PODS -eq $TOTAL_PODS ]; then
        echo -e "${GREEN}🎉 Near-RT RIC Platform is fully operational!${NC}"
    else
        echo -e "${YELLOW}⚠️  Near-RT RIC Platform is partially operational${NC}"
    fi
else
    echo -e "${RED}❌ Near-RT RIC Platform is not operational${NC}"
fi

if [ $XAPP_RUNNING -gt 0 ]; then
    echo -e "${GREEN}📱 xApps are running${NC}"
fi

if [ $E2SIM_PODS -gt 0 ]; then
    echo -e "${GREEN}🔌 E2 Simulator is available${NC}"
fi

echo ""
echo -e "${BLUE}💡 Useful Commands:${NC}"
echo "   • Detailed pod status: kubectl get pods -A"
echo "   • RIC logs: kubectl logs <pod-name> -n ricplt"
echo "   • Services: kubectl get svc -n ricplt"
echo "   • Events: kubectl get events -A --sort-by='.lastTimestamp'"
echo ""
echo -e "${BLUE}📚 Documentation:${NC}"
echo "   • Deployment Report: docs/deployment-report.md"
echo "   • Troubleshooting: troubleshooting/issues.md"
echo "   • Logs Directory: deployment/logs/"
echo ""
