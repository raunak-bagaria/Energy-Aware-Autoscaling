#!/bin/bash

# Phase 2: CPU HPA Testing Script for 20-service Mixed Workload
# This script implements Phase 2 with traditional CPU-based Horizontal Pod Autoscaling

set -e  # Exit on any error

echo "⚙️ PHASE 2: CPU HPA Testing (20-Service Mixed Workload)"
e# Collect data for 3 minutes
log_action "📈 Collecting CPU HPA CPU-intensive data for 3 minutes..."
python3 research_data_collector.py --mode experiment --scenario cpu_hpa_cpu_intensive_mixed --duration 180 & "======================================================="
echo "⏰ Start time: $(date)"
echo "🎯 Goal: Test traditional CPU-based autoscaling"
echo "🧮 Workload: 20-service heterogeneous workload (CPU+Memory+I/O)"
echo "📊 Services: s0[Gateway], s1-s2,s5-s6[Memory], s4[I/O], s8,s10-s19[CPU]"
echo "⚡ Optimized: Short durations, consistent timing for comparison"
echo "======================================================="

# Configuration for 20-service setup
GATEWAY_URL="http://192.168.49.2:31113"
PROMETHEUS_URL="http://192.168.49.2:30000"
EXPERIMENT_START_TIME=$(date +%Y%m%d_%H%M%S)
LOG_FILE="phase2_mixed_log_${EXPERIMENT_START_TIME}.txt"
NAMESPACE="default"

# Define services by workload type (based on actual workmodel)
GATEWAY_SERVICES=("s0")                                           # Gateway service (no stress)
MEMORY_SERVICES=("s1" "s2" "s6" "s9" "s12" "s13")                # Memory stress services
IO_SERVICES=("s3" "s4" "s5" "s7" "s10" "s11" "s14" "s15" "s16" "s17" "s18" "s19")  # Disk I/O services
CPU_SERVICES=("s8")                                               # Pure CPU service (π computation)
ALL_SERVICES=("s0" "s1" "s2" "s3" "s4" "s5" "s6" "s7" "s8" "s9" "s10" "s11" "s12" "s13" "s14" "s15" "s16" "s17" "s18" "s19")

# CPU HPA Parameters (optimized for mixed workload)
CPU_TARGET_PERCENTAGE=50  # Lower threshold for mixed workload responsiveness
MIN_REPLICAS=1
MAX_REPLICAS=3           # Conservative for 20-service setup
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

# Function to create CPU HPA for mixed workload
create_cpu_hpa() {
    log_action "🔧 Creating CPU HPA for 20-service mixed workload..."
    
    for service in "${ALL_SERVICES[@]}"; do
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
}

# Function to check if services are running
check_services() {
    log_action "🔍 Checking if 20-service mixed workload is running..."
    local missing_services=()
    for service in "${ALL_SERVICES[@]}"; do
        if ! kubectl get deployment "$service" -n "$NAMESPACE" >/dev/null 2>&1; then
            missing_services+=("$service")
        fi
    done
    
    if [ ${#missing_services[@]} -gt 0 ]; then
        log_action "❌ ERROR: Missing services: ${missing_services[*]}"
        log_action "💡 Please deploy 20-service mixed workmodel first."
        exit 1
    fi
    log_action "✅ All 20 mixed workload services are running"
}

# Function to check gateway connectivity
check_gateway() {
    log_action "🌐 Checking gateway connectivity..."
    if ! curl -s --connect-timeout 5 "$GATEWAY_URL" > /dev/null; then
        log_action "⚠️  WARNING: Gateway at $GATEWAY_URL might not be accessible"
        log_action "📝 You can find the correct gateway URL with: kubectl get svc gw-nginx"
    else
        log_action "✅ Gateway is accessible"
    fi
}

# Function to show HPA status
show_hpa_status() {
    log_action "📊 Current HPA Status:"
    kubectl get hpa -o wide | tee -a "$LOG_FILE"
}

# Function to display workload characteristics
show_workload_info() {
    log_action "🧮 MIXED WORKLOAD CHARACTERISTICS:"
    log_action "📊 Gateway Services: ${GATEWAY_SERVICES[*]} (orchestration only)"
    log_action "🧠 Memory Services: ${MEMORY_SERVICES[*]} (50MB memory stress)"
    log_action "💾 I/O Services: ${IO_SERVICES[*]} (disk write operations)"
    log_action "⚡ CPU Services: ${CPU_SERVICES[*]} (π computation: 800 digits, 2 trials)"
    log_action "🔗 Complex service dependencies across all workload types"
}

# Step 0: Verify environment
check_services
check_gateway
show_workload_info

# Step 1: Clean up any existing HPAs and reset services
log_action "🧹 Step 1: Cleaning up existing HPAs..."
kubectl delete hpa --all --ignore-not-found=true
wait_with_countdown 30 "HPA cleanup"

# Reset all services to 1 replica
log_action "🔄 Resetting all services to 1 replica..."
for service in "${ALL_SERVICES[@]}"; do
    kubectl scale deployment "$service" --replicas=1 -n "$NAMESPACE"
done
wait_with_countdown 45 "service reset and mixed workload stabilization"

# Step 2: Create CPU HPAs for all services
create_cpu_hpa
wait_with_countdown 60 "HPA creation and initialization"

# Show initial state
log_action "📊 Initial 20-service mixed workload state with CPU HPA:"
show_hpa_status
for service in "${ALL_SERVICES[@]}"; do
    replicas=$(get_current_replicas "$service")
    log_action "  $service: $replicas replicas"
done

# Step 3: Test 1 - CPU HPA with Constant Medium Load
log_action "🧪 Step 3: Test 1 - CPU HPA with Constant Medium Load (mixed workload)..."

# Start load test
python3 load_tester.py --gateway "$GATEWAY_URL" --workload constant --rps 8 --duration 180 &
LOAD_PID=$!

# Wait for load to stabilize and HPAs to react
wait_with_countdown 30 "load warmup and HPA stabilization"

# Collect data for 3 minutes
log_action "📈 Collecting CPU HPA constant load data for 3 minutes..."
python3 research_data_collector.py --mode experiment --scenario cpu_hpa_constant_medium_mixed --duration 180 &
COLLECT_PID=$!

# Monitor scaling every 30 seconds
for i in {1..6}; do
    wait_with_countdown 30 "monitoring HPA scaling (check $i/6)"
    show_hpa_status
done

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ Data collection completed"

# Wait for load test to finish
wait $LOAD_PID
log_action "✅ Load test completed"

# Cool down period
wait_with_countdown 45 "system cooldown and HPA stabilization"

# Step 4: Test 2 - CPU HPA with Burst Load
log_action "🧪 Step 4: Test 2 - CPU HPA with Burst Load (mixed workload)..."

# Start burst load test
python3 load_tester.py --gateway "$GATEWAY_URL" --workload burst --rps 12 --duration 180 &
LOAD_PID=$!

# Wait for load to stabilize
wait_with_countdown 30 "burst load warmup and HPA reaction"

# Collect data for 3 minutes
log_action "📈 Collecting CPU HPA burst data for 3 minutes..."
python3 research_data_collector.py --mode experiment --scenario cpu_hpa_burst_mixed --duration 180 &
COLLECT_PID=$!

# Monitor scaling every 30 seconds
for i in {1..6}; do
    wait_with_countdown 30 "monitoring burst HPA scaling (check $i/6)"
    show_hpa_status
done

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ Burst data collection completed"

# Wait for load test to finish
wait $LOAD_PID
log_action "✅ Burst load test completed"

# Cool down period
wait_with_countdown 45 "system cooldown and HPA reset"

# Step 5: Test 3 - CPU HPA with CPU Intensive Load
log_action "🧪 Step 5: Test 3 - CPU HPA with CPU Intensive Load (mixed workload)..."

# Start CPU intensive load test
python3 load_tester.py --gateway "$GATEWAY_URL" --workload cpu_intensive --rps 6 --duration 240 &
LOAD_PID=$!

# Wait for load to stabilize
wait_with_countdown 30 "CPU intensive load warmup and HPA reaction"

# Collect data for 3 minutes
log_action "📈 Collecting CPU HPA intensive data for 3 minutes..."
python3 research_data_collector.py --mode experiment --scenario cpu_hpa_cpu_intensive_mixed --duration 3 &
COLLECT_PID=$!

# Monitor scaling every 30 seconds during intense period
for i in {1..6}; do
    wait_with_countdown 30 "monitoring intensive HPA scaling (check $i/6)"
    show_hpa_status
done

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ CPU intensive data collection completed"

# Wait for load test to finish
wait $LOAD_PID
log_action "✅ CPU intensive load test completed"

# Step 6: Show final results
log_action "📊 Step 6: Phase 2 Results Summary"
log_action "=================================="

# Show final replica counts and HPA status
log_action "🔍 Final replica counts and HPA status:"
show_hpa_status
for service in "${ALL_SERVICES[@]}"; do
    replicas=$(get_current_replicas "$service")
    log_action "  $service: $replicas replicas"
done

# List generated data files
log_action "📁 Generated data files:"
ls -la research_data/cpu_hpa_*_mixed* 2>/dev/null | tee -a "$LOG_FILE" || log_action "No CPU HPA data files found yet"

log_action "🎉 PHASE 2 COMPLETED SUCCESSFULLY!"
log_action "=================================="
log_action "⏰ End time: $(date)"
log_action "📁 Results in: research_data/"
log_action "📄 Log file: $LOG_FILE"
log_action "🧮 Workload: 20-service mixed workload with CPU HPA"
log_action "💡 Next: Run Phase 3 (Energy-Aware HPA) for comparison"

echo ""
echo "📊 PHASE 2 DATA SUMMARY:"
echo "========================"
echo "✅ CPU HPA constant medium load: cpu_hpa_constant_medium_mixed_*.csv"
echo "✅ CPU HPA burst load: cpu_hpa_burst_mixed_*.csv"  
echo "✅ CPU HPA CPU intensive load: cpu_hpa_cpu_intensive_mixed_*.csv"
echo ""
echo "🧮 MIXED WORKLOAD SCALING EXPECTATIONS:"
echo "⚡ CPU services (s8): Expected most scaling (high CPU usage from π computation)"
echo "🧠 Memory services (s1,s2,s6,s9,s12,s13): Moderate scaling (memory pressure)"
echo "💾 I/O services (s3-s5,s7,s10,s11,s14-s19): Moderate scaling (I/O wait states)"
echo "📊 Gateway (s0): Minimal scaling (orchestration only)"
echo ""
echo "🔍 CPU HPA Target: ${CPU_TARGET_PERCENTAGE}% CPU utilization"
echo "📈 Max Replicas: ${MAX_REPLICAS} per service"
