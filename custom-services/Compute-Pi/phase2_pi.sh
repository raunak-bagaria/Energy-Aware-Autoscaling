#!/bin/bash

# Phase 2: CPU HPA Testing Script for 4-service compute_pi workload
# This script implements Phase 2 with traditional CPU-based Horizontal Pod Autoscaling

set -e  # Exit on any error

echo "⚙️ PHASE 2: CPU HPA Testing (4-Service compute_pi)"
echo "================================================="
echo "⏰ Start time: $(date)"
echo "🎯 Goal: Test traditional CPU-based autoscaling"
echo "🧮 Workload: 4-service π computation with HIGH complexity"
echo "📊 Services: s0[π400-600], s1[π1500-2500], s2[π800-1200], s3[π200-400]"
echo "⚡ Optimized: Short durations, consistent timing for comparison"
echo "================================================="

# Configuration for 4-service setup
GATEWAY_URL="http://192.168.49.2:31113"
PROMETHEUS_URL="http://192.168.49.2:30000"
EXPERIMENT_START_TIME=$(date +%Y%m%d_%H%M%S)
LOG_FILE="phase2_4services_log_${EXPERIMENT_START_TIME}.txt"
NAMESPACE="default"
SERVICES=("s0" "s1" "s2" "s3")  # Updated for 4-service workmodel

# CPU HPA Parameters (optimized for compute_pi workload)
CPU_TARGET_PERCENTAGE=60  # CPU threshold for HPA
MIN_REPLICAS=1
MAX_REPLICAS=4           # Reduced from 5 for 4-service setup
HPA_INTERVAL=30          # HPA check interval

# Working Prometheus queries for RPS and latency
RPS_QUERY='sum by (app_name) (rate(mub_internal_processing_latency_milliseconds_count{}[2m]))'
SERVICE_DELAY_QUERY='sum by (app_name) (increase(mub_request_processing_latency_milliseconds_sum{}[2m])) / sum by (app_name) (increase(mub_request_processing_latency_milliseconds_count{}[2m]))'
INTERNAL_DELAY_QUERY='sum by (app_name) (increase(mub_internal_processing_latency_milliseconds_sum{}[2m])) / sum by (app_name) (increase(mub_internal_processing_latency_milliseconds_count{}[2m]))'
EXTERNAL_DELAY_QUERY='sum by (app_name) (increase(mub_external_processing_latency_milliseconds_sum{}[2m])) / sum by (app_name) (increase(mub_external_processing_latency_milliseconds_count{}[2m]))'

# Function to log with timestamp
log_action() {
    local message="$1"
    local timestamp=$(date '+%H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# Function to wait with countdown
wait_with_countdown() {
    local duration=$1
    local description="$2"
    log_action "⏳ Waiting $duration seconds for $description..."
    for ((i=duration; i>0; i--)); do
        printf "\r⏳ $description: %02d seconds remaining" $i
        sleep 1
    done
    printf "\n"
}

# Function to get current replicas
get_current_replicas() {
    local service="$1"
    kubectl get deployment "$service" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1"
}

# Function to create CPU HPA for 4-service setup
create_cpu_hpa() {
    log_action "🔧 Creating CPU HPA for 4-service compute_pi workload..."
    
    for service in "${SERVICES[@]}"; do
        cat << EOF | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ${service}-cpu-hpa
  namespace: ${NAMESPACE}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ${service}
  minReplicas: ${MIN_REPLICAS}
  maxReplicas: ${MAX_REPLICAS}
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: ${CPU_TARGET_PERCENTAGE}
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
    scaleDown:
      stabilizationWindowSeconds: 180
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
EOF
        log_action "  ✅ Created CPU HPA for $service (target: ${CPU_TARGET_PERCENTAGE}%)"
    done
    
    # Wait for HPA to initialize
    wait_with_countdown 30 "HPA initialization and π computation baseline"
}

# Function to check HPA status
check_hpa_status() {
    log_action "📊 Current CPU HPA status for 4-service compute_pi:"
    log_action "=" * 80
    for service in "${SERVICES[@]}"; do
        local hpa_info=$(kubectl get hpa "${service}-cpu-hpa" -n "$NAMESPACE" --no-headers 2>/dev/null || echo "N/A N/A N/A N/A")
        local current_replicas=$(get_current_replicas "$service")
        log_action "  $service: $current_replicas replicas, HPA: $hpa_info"
    done
    log_action "=" * 80
}

# Function to remove CPU HPA
remove_cpu_hpa() {
    log_action "🧹 Removing CPU HPA for 4-service setup..."
    for service in "${SERVICES[@]}"; do
        kubectl delete hpa "${service}-cpu-hpa" -n "$NAMESPACE" --ignore-not-found=true
        log_action "  ✅ Removed CPU HPA for $service"
    done
}

# Function to check if services are running
check_services() {
    log_action "🔍 Checking if 4-service compute_pi workload is running..."
    for service in "${SERVICES[@]}"; do
        if ! kubectl get deployment "$service" -n "$NAMESPACE" >/dev/null 2>&1; then
            log_action "❌ ERROR: Service $service not found! Please deploy 4-service workmodel first."
            exit 1
        fi
    done
    log_action "✅ All 4 compute_pi services are running"
}

# Step 0: Verify environment
check_services

# Step 1: Clean up any existing HPAs and reset replicas
log_action "🧹 Step 1: Cleaning up existing HPAs and resetting replicas..."
kubectl delete hpa --all --ignore-not-found=true -n "$NAMESPACE"

# Reset all services to 1 replica
for service in "${SERVICES[@]}"; do
    kubectl scale deployment "$service" --replicas=1 -n "$NAMESPACE"
done
wait_with_countdown 30 "service reset and π computation stabilization"

# Step 2: Create CPU HPA for all services
log_action "⚙️ Step 2: Setting up CPU HPA for 4-service compute_pi..."
create_cpu_hpa

# Show initial HPA state
check_hpa_status

# Step 3: Test 1 - CPU HPA with Constant Medium Load
log_action "🧪 Step 3: Test 1 - CPU HPA with Constant Medium Load (compute_pi)..."

# Start load test (reduced duration to match Phase 3 timing)
python3 load_tester.py --gateway "$GATEWAY_URL" --workload constant --rps 10 --duration 120 &
LOAD_PID=$!

# Wait for load to stabilize and trigger HPA
wait_with_countdown 15 "load warmup and CPU HPA triggering for π computation"

# Monitor HPA for a bit
check_hpa_status

# Collect data for 2 minutes (reduced to match Phase 3)
log_action "📈 Collecting CPU HPA data for 2 minutes..."
python3 research_data_collector.py --mode experiment --scenario cpu_hpa_constant_medium_4svc --duration 2 &
COLLECT_PID=$!

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ Data collection completed"

# Wait for load test to finish
wait $LOAD_PID
log_action "✅ Load test completed"

# Show HPA results
check_hpa_status

# Cool down period
wait_with_countdown 30 "system cooldown and HPA stabilization"

# Step 4: Test 2 - CPU HPA with Burst Load
log_action "🧪 Step 4: Test 2 - CPU HPA with Burst Load (compute_pi)..."

# Start burst load test (reduced duration to match Phase 3 timing)
python3 load_tester.py --gateway "$GATEWAY_URL" --workload burst --rps 15 --duration 120 &
LOAD_PID=$!

# Wait for load to stabilize and trigger HPA
wait_with_countdown 15 "burst load warmup and CPU HPA response to π computation"

# Monitor HPA
check_hpa_status

# Collect data for 2 minutes (reduced to match Phase 3)
log_action "📈 Collecting CPU HPA burst data for 2 minutes..."
python3 research_data_collector.py --mode experiment --scenario cpu_hpa_burst_4svc --duration 2 &
COLLECT_PID=$!

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ Burst data collection completed"

# Wait for load test to finish
wait $LOAD_PID
log_action "✅ Burst load test completed"

# Show HPA results
check_hpa_status

# Cool down period
wait_with_countdown 30 "system cooldown and HPA stabilization"

# Step 5: Test 3 - CPU HPA with CPU Intensive Load
log_action "🧪 Step 5: Test 3 - CPU HPA with CPU Intensive Load (compute_pi)..."

# Start CPU intensive load test (keeping 240s duration like Phase 3)
python3 load_tester.py --gateway "$GATEWAY_URL" --workload cpu_intensive --rps 8 --duration 240 &
LOAD_PID=$!

# Wait for load to stabilize and trigger aggressive HPA
wait_with_countdown 30 "CPU intensive load warmup and aggressive HPA for heavy π computation"

# Monitor HPA
check_hpa_status

# Collect data for 3 minutes (keeping same as Phase 3)
log_action "📈 Collecting CPU HPA intensive data for 3 minutes..."
python3 research_data_collector.py --mode experiment --scenario cpu_hpa_cpu_intensive_4svc --duration 3 &
COLLECT_PID=$!

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ CPU intensive data collection completed"

# Wait for load test to finish
wait $LOAD_PID
log_action "✅ CPU intensive load test completed"

# Final HPA status
check_hpa_status

# Step 6: Clean up and show results
log_action "🧹 Step 6: Cleaning up CPU HPA..."
remove_cpu_hpa

log_action "📊 Step 6: Phase 2 Results Summary"
log_action "=================================="

# Show final replica counts
log_action "🔍 Final replica counts after CPU HPA:"
for service in "${SERVICES[@]}"; do
    replicas=$(get_current_replicas "$service")
    log_action "  $service: $replicas replicas"
done

# List generated data files
log_action "📁 Generated data files:"
ls -la research_data/cpu_hpa_*_4svc* 2>/dev/null | tee -a "$LOG_FILE" || log_action "No CPU HPA data files found yet"

log_action "🎉 PHASE 2 COMPLETED SUCCESSFULLY!"
log_action "=================================="
log_action "⏰ End time: $(date)"
log_action "📁 Results in: research_data/"
log_action "📄 Log file: $LOG_FILE"
log_action "🧮 Workload: 4-service compute_pi with CPU HPA"
log_action "📊 Services tested: s0[π100-200], s1[π400-600], s2[π200-400], s3[π50-150]"
log_action "💡 Next: Run Phase 3 (Energy-Aware) for comparison"

echo ""
echo "📊 PHASE 2 DATA SUMMARY:"
echo "========================"
echo "✅ CPU HPA constant medium load: cpu_hpa_constant_medium_4svc_*.csv"
echo "✅ CPU HPA burst load: cpu_hpa_burst_4svc_*.csv"  
echo "✅ CPU HPA CPU intensive load: cpu_hpa_cpu_intensive_4svc_*.csv"
echo ""
echo "🧮 CPU HPA BEHAVIOR WITH COMPUTE_PI:"
echo "📈 Expected s1 scaling: Highest (π[400-600] complexity)"
echo "📈 Expected s2 scaling: Medium (π[200-400])"
echo "📈 Expected s0 scaling: Low-Medium (orchestration + π[100-200])"
echo "📈 Expected s3 scaling: Lowest (π[50-150])"
echo ""
echo "🔍 Compare with Phase 1 baseline and Phase 3 energy-aware results!"
