#!/bin/bash

# Phase 1: Baseline Testing Script for 4-service compute_pi workload
# This script implements Phase 1 with no autoscaling for pure baseline data

set -e  # Exit on any error

echo "📊 PHASE 1: Baseline Testing (4-Service compute_pi)"
echo "================================================="
echo "⏰ Start time: $(date)"
echo "🎯 Goal: Collect baseline data without autoscaling"
echo "🧮 Workload: 4-service π computation with HIGH complexity"
echo "📊 Services: s0[π100-200], s1[π400-600], s2[π200-400], s3[π50-150]"
echo "⚡ Optimized: Short durations, consistent timing for comparison"
echo "================================================="

# Configuration for 4-service setup
GATEWAY_URL="http://192.168.49.2:31113"
PROMETHEUS_URL="http://192.168.49.2:30000"
EXPERIMENT_START_TIME=$(date +%Y%m%d_%H%M%S)
LOG_FILE="phase1_4services_log_${EXPERIMENT_START_TIME}.txt"
NAMESPACE="default"
SERVICES=("s0" "s1" "s2" "s3")  # Updated for 4-service workmodel

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

# Step 0: Verify environment
check_services
check_gateway

# Step 1: Clean up any existing HPAs
log_action "🧹 Step 1: Ensuring no autoscaling (baseline)..."
kubectl delete hpa --all --ignore-not-found=true
wait_with_countdown 30 "HPA cleanup"

# Step 2: Reset all services to 1 replica for consistent baseline
log_action "🔄 Step 2: Resetting all services to 1 replica..."
for service in "${SERVICES[@]}"; do
    kubectl scale deployment "$service" --replicas=1 -n "$NAMESPACE"
    log_action "  $service: Set to 1 replica"
done
wait_with_countdown 30 "service reset and π computation stabilization"

# Show initial state
log_action "📊 Initial 4-service state:"
for service in "${SERVICES[@]}"; do
    replicas=$(get_current_replicas "$service")
    log_action "  $service: $replicas replicas (baseline)"
done

# Step 3: Test 1 - Baseline with Constant Medium Load
log_action "🧪 Step 3: Test 1 - Baseline with Constant Medium Load (compute_pi)..."
log_action "📊 Starting load generation and data collection..."

# Start load test (reduced duration to match Phase 3 timing)
python3 load_tester.py --gateway "$GATEWAY_URL" --workload constant --rps 10 --duration 120 &
LOAD_PID=$!

# Wait for load to stabilize
wait_with_countdown 15 "load warmup and π computation stabilization"

# Collect data for 2 minutes (reduced to match Phase 3)
log_action "📈 Collecting baseline data for 2 minutes..."
python3 research_data_collector.py --mode experiment --scenario baseline_constant_medium_4svc --duration 2 &
COLLECT_PID=$!

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ Data collection completed"

# Wait for load test to finish
wait $LOAD_PID
log_action "✅ Load test completed"

# Cool down period
wait_with_countdown 30 "system cooldown and π computation reset"

# Step 4: Test 2 - Baseline with Burst Load
log_action "🧪 Step 4: Test 2 - Baseline with Burst Load (compute_pi)..."

# Start burst load test (reduced duration to match Phase 3 timing)
python3 load_tester.py --gateway "$GATEWAY_URL" --workload burst --rps 15 --duration 120 &
LOAD_PID=$!

# Wait for load to stabilize
wait_with_countdown 30 "burst load warmup and π computation"

# Collect data for 3 minutes
log_action "📈 Collecting baseline burst data for 3 minutes..."
python3 research_data_collector.py --mode experiment --scenario baseline_burst_4svc --duration 3 &
COLLECT_PID=$!

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ Burst data collection completed"

# Wait for load test to finish
wait $LOAD_PID
log_action "✅ Burst load test completed"

# Cool down period
wait_with_countdown 30 "system cooldown and π computation reset"

# Step 5: Test 3 - Baseline with CPU Intensive Load
log_action "🧪 Step 5: Test 3 - Baseline with CPU Intensive Load (compute_pi)..."

# Start CPU intensive load test (keeping 240s duration like Phase 3)
python3 load_tester.py --gateway "$GATEWAY_URL" --workload cpu_intensive --rps 8 --duration 240 &
LOAD_PID=$!

# Wait for load to stabilize
wait_with_countdown 30 "CPU intensive load warmup and heavy π computation"

# Collect data for 3 minutes (keeping same as Phase 3)
log_action "📈 Collecting baseline CPU intensive data for 3 minutes..."
python3 research_data_collector.py --mode experiment --scenario baseline_cpu_intensive_4svc --duration 3 &
COLLECT_PID=$!

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ CPU intensive data collection completed"

# Wait for load test to finish
wait $LOAD_PID
log_action "✅ CPU intensive load test completed"

# Step 6: Show results
log_action "📊 Step 6: Phase 1 Results Summary"
log_action "=================================="

# Show final replica counts (should all be 1)
log_action "🔍 Final replica counts (baseline - no autoscaling):"
for service in "${SERVICES[@]}"; do
    replicas=$(get_current_replicas "$service")
    log_action "  $service: $replicas replicas"
done

# List generated data files
log_action "📁 Generated data files:"
ls -la research_data/baseline_*_4svc* 2>/dev/null | tee -a "$LOG_FILE" || log_action "No baseline data files found yet"

log_action "🎉 PHASE 1 COMPLETED SUCCESSFULLY!"
log_action "=================================="
log_action "⏰ End time: $(date)"
log_action "📁 Results in: research_data/"
log_action "📄 Log file: $LOG_FILE"
log_action "🧮 Workload: 4-service compute_pi with graduated complexity"
log_action "📊 Services tested: s0[π100-200], s1[π400-600], s2[π200-400], s3[π50-150]"
log_action "💡 Next: Run Phase 2 (CPU HPA) for comparison"

echo ""
echo "📊 PHASE 1 DATA SUMMARY:"
echo "========================"
echo "✅ Baseline constant medium load: baseline_constant_medium_4svc_*.csv"
echo "✅ Baseline burst load: baseline_burst_4svc_*.csv"  
echo "✅ Baseline CPU intensive load: baseline_cpu_intensive_4svc_*.csv"
echo ""
echo "🧮 COMPUTE_PI WORKLOAD CHARACTERISTICS:"
echo "📈 s0: Frontend + π[100-200] (orchestrator)"
echo "📈 s0: π[400-600] (gateway complexity)"
echo "📈 s1: π[1500-2500] (highest complexity)"
echo "📈 s2: π[800-1200] (high complexity)" 
echo "📈 s3: π[200-400] (moderate complexity)"
echo ""
echo "🔍 Expected energy gradient: s1 > s2 > s0 > s3"
