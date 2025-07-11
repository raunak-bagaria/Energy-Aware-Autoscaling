#!/bin/bash

# Phase 1: Baseline Testing Script for 7-service Mixed Workload
# This script implements Phase 1 with no autoscaling for pure baseline data

set -e  # Exit on any error

echo "📊 PHASE 1: Baseline Testing (7-Service Mixed Workload)"
echo "========================================================"
echo "⏰ Start time: $(date)"
echo "🎯 Goal: Collect baseline data without autoscaling"
echo "🧮 Workload: 7-service heterogeneous workload (CPU+Memory+I/O)"
echo "📊 Services: s0[Gateway], s1-s2[Memory], s3-s4[I/O], s5[CPU], s6[CPU+Memory]"
echo "⚡ Optimized: Short durations, consistent timing for comparison"
echo "========================================================"

# Configuration for 7-service setup
GATEWAY_URL="http://192.168.49.2:31113"
PROMETHEUS_URL="http://192.168.49.2:30000"
EXPERIMENT_START_TIME=$(date +%Y%m%d_%H%M%S)
LOG_FILE="phase1_mixed_log_${EXPERIMENT_START_TIME}.txt"
NAMESPACE="default"

# Define services by workload type for better monitoring (based on actual workmodel)
GATEWAY_SERVICES=("s0")                                           # Gateway service (no stress)
MEMORY_SERVICES=("s1" "s2")                                       # Memory stress services
IO_SERVICES=("s3" "s4")                                           # Disk I/O services
CPU_SERVICES=("s5")                                               # Pure CPU service (π computation)
MIXED_SERVICES=("s6")                                             # Services with both CPU and Memory
ALL_SERVICES=("s0" "s1" "s2" "s3" "s4" "s5" "s6")

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
    log_action "🔍 Checking if 7-service mixed workload is running..."
    local missing_services=()
    for service in "${ALL_SERVICES[@]}"; do
        if ! kubectl get deployment "$service" -n "$NAMESPACE" >/dev/null 2>&1; then
            missing_services+=("$service")
        fi
    done
    
    if [ ${#missing_services[@]} -gt 0 ]; then
        log_action "❌ ERROR: Missing services: ${missing_services[*]}"
        log_action "💡 Please deploy 7-service mixed workmodel first."
        exit 1
    fi
    log_action "✅ All 7 mixed workload services are running"
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

# Function to check Prometheus connectivity
check_prometheus() {
    log_action "📊 Checking Prometheus connectivity..."
    if ! curl -s --connect-timeout 5 "$PROMETHEUS_URL" > /dev/null; then
        log_action "⚠️  WARNING: Prometheus at $PROMETHEUS_URL might not be accessible"
        log_action "📝 This may cause metric collection to fail"
        return 1
    else
        log_action "✅ Prometheus is accessible"
        return 0
    fi
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
check_prometheus
show_workload_info

# Verify research_data directory exists
if [ ! -d "research_data" ]; then
    log_action "📁 Creating research_data directory..."
    mkdir -p research_data
fi

# Step 1: Clean up any existing HPAs
log_action "🧹 Step 1: Ensuring no autoscaling (baseline)..."
kubectl delete hpa --all --ignore-not-found=true
wait_with_countdown 30 "HPA cleanup"

# Step 2: Reset all services to 1 replica for consistent baseline
log_action "🔄 Step 2: Resetting all services to 1 replica..."
for service in "${ALL_SERVICES[@]}"; do
    kubectl scale deployment "$service" --replicas=1 -n "$NAMESPACE"
    log_action "  $service: Set to 1 replica"
done
wait_with_countdown 45 "service reset and mixed workload stabilization"

# Show initial state
log_action "📊 Initial 7-service mixed workload state:"
for service in "${ALL_SERVICES[@]}"; do
    replicas=$(get_current_replicas "$service")
    log_action "  $service: $replicas replicas (baseline)"
done

# Step 3: Test 1 - Baseline with Constant Medium Load
log_action "🧪 Step 3: Test 1 - Baseline with Constant Medium Load (mixed workload)..."
log_action "📊 Starting load generation and data collection..."

# Start load test - appropriate RPS for 7-service workload
log_action "🧪 Running load test with params: --gateway $GATEWAY_URL --workload constant --rps 6 --duration 150 --service s0"
python3 load_tester.py --gateway "$GATEWAY_URL" --workload constant --rps 6 --duration 150 --service s0 &
LOAD_PID=$!

# Test direct gateway access to verify connectivity
log_action "🧪 Testing direct gateway access to verify connectivity..."
curl -s "$GATEWAY_URL/s0" > /dev/null && log_action "✅ Gateway /s0 access successful" || log_action "❌ Gateway /s0 access failed"

# Wait for load to stabilize
wait_with_countdown 20 "load warmup and mixed workload stabilization"

# Collect data for 2.5 minutes
log_action "📈 Collecting baseline data for 2.5 minutes..."
# Duration is in minutes in the research_data_collector.py - must use integer minutes
log_action "🧪 Running data collector with params: --mode experiment --scenario baseline_constant_medium_mixed --duration 3 --prometheus-url $PROMETHEUS_URL"
python3 research_data_collector.py --mode experiment --scenario baseline_constant_medium_mixed --duration 3 --prometheus-url "$PROMETHEUS_URL" &
COLLECT_PID=$!

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ Data collection completed"

# Check for any generated data files
log_action "🔍 Checking for data files from this run..."
ls -la research_data/baseline_constant_medium_mixed_* 2>/dev/null && log_action "✅ Data files found" || log_action "⚠️ No data files found for this run"

# Wait for load test to finish
wait $LOAD_PID
log_action "✅ Load test completed"

# Check prometheus metrics for s0 to verify they're being collected
log_action "🔍 Checking for Prometheus metrics for s0..."
curl -s "$PROMETHEUS_URL/api/v1/query?query=rate(servicecell_request_count{service=%22s0%22}[1m])" | grep -q "value" && log_action "✅ Metrics found for s0" || log_action "⚠️ No metrics found for s0"

# Kill any remaining research_data_collector.py processes to avoid continued metric collection
pkill -f "python3 research_data_collector.py" || true

# Cool down period
wait_with_countdown 30 "system cooldown and workload reset"

# Step 4: Test 2 - Baseline with Burst Load
log_action "🧪 Step 4: Test 2 - Baseline with Burst Load (mixed workload)..."

# Start burst load test - adjusted for mixed complexity
log_action "🧪 Running burst load test with params: --gateway $GATEWAY_URL --workload burst --rps 8 --duration 150 --service s0"
python3 load_tester.py --gateway "$GATEWAY_URL" --workload burst --rps 8 --duration 150 --service s0 &
LOAD_PID=$!

# Wait for load to stabilize
wait_with_countdown 30 "burst load warmup and mixed workload processing"

# Collect data for 3 minutes
log_action "📈 Collecting baseline burst data for 3 minutes..."
# Duration is in minutes in the research_data_collector.py - must use integer minutes
log_action "🧪 Running data collector with params: --mode experiment --scenario baseline_burst_mixed --duration 3 --prometheus-url $PROMETHEUS_URL"
python3 research_data_collector.py --mode experiment --scenario baseline_burst_mixed --duration 3 --prometheus-url "$PROMETHEUS_URL" &
COLLECT_PID=$!

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ Burst data collection completed"

# Check for any generated data files
log_action "🔍 Checking for data files from this burst run..."
ls -la research_data/baseline_burst_mixed_* 2>/dev/null && log_action "✅ Burst data files found" || log_action "⚠️ No burst data files found for this run"

# Wait for load test to finish
wait $LOAD_PID
log_action "✅ Burst load test completed"

# Kill any remaining research_data_collector.py processes to avoid continued metric collection
pkill -f "python3 research_data_collector.py" || true

# Cool down period
wait_with_countdown 30 "system cooldown and workload reset"

# Step 5: Test 3 - Baseline with CPU Intensive Load
log_action "🧪 Step 5: Test 3 - Baseline with CPU Intensive Load (mixed workload)..."

# Start CPU intensive load test - appropriate for 7-service complexity
log_action "🧪 Running CPU intensive load test with params: --gateway $GATEWAY_URL --workload cpu_intensive --rps 4 --duration 240 --service s5"
python3 load_tester.py --gateway "$GATEWAY_URL" --workload cpu_intensive --rps 4 --duration 240 --service s5 &
LOAD_PID=$!

# Wait for load to stabilize
wait_with_countdown 30 "CPU intensive load warmup and heavy mixed computation"

# Collect data for 3 minutes
log_action "📈 Collecting baseline CPU intensive data for 3 minutes..."
# Duration is in minutes in the research_data_collector.py, so 4 minutes = 240 seconds
log_action "🧪 Running data collector with params: --mode experiment --scenario baseline_cpu_intensive_mixed --duration 4 --prometheus-url $PROMETHEUS_URL"
python3 research_data_collector.py --mode experiment --scenario baseline_cpu_intensive_mixed --duration 4 --prometheus-url "$PROMETHEUS_URL" &
COLLECT_PID=$!

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ CPU intensive data collection completed"

# Check for any generated data files
log_action "🔍 Checking for data files from this CPU intensive run..."
ls -la research_data/baseline_cpu_intensive_mixed_* 2>/dev/null && log_action "✅ CPU intensive data files found" || log_action "⚠️ No CPU intensive data files found for this run"

# Wait for load test to finish
wait $LOAD_PID
log_action "✅ CPU intensive load test completed"

# Kill any remaining research_data_collector.py processes to avoid continued metric collection
pkill -f "python3 research_data_collector.py" || true

# Step 6: Show results
log_action "📊 Step 6: Phase 1 Results Summary"
log_action "=================================="

# Show final replica counts (should all be 1)
log_action "🔍 Final replica counts (baseline - no autoscaling):"
for service in "${ALL_SERVICES[@]}"; do
    replicas=$(get_current_replicas "$service")
    log_action "  $service: $replicas replicas"
done

# List generated data files
log_action "📁 Generated data files:"
ls -la research_data/baseline_*_mixed* 2>/dev/null | tee -a "$LOG_FILE" || log_action "No baseline data files found yet"

# Ensure we clean up any lingering processes
pkill -f "python3 research_data_collector.py" || true
pkill -f "python3 load_tester.py" || true

log_action "🎉 PHASE 1 COMPLETED SUCCESSFULLY!"
log_action "=================================="
log_action "⏰ End time: $(date)"
log_action "📁 Results in: research_data/"
log_action "📄 Log file: $LOG_FILE"
log_action "🧮 Workload: 7-service mixed workload (CPU+Memory+I/O)"
log_action "💡 Next: Run Phase 2 (CPU HPA) for comparison"

echo ""
echo "📊 PHASE 1 DATA SUMMARY:"
echo "========================"
echo "✅ Baseline constant medium load: baseline_constant_medium_mixed_*.csv"
echo "✅ Baseline burst load: baseline_burst_mixed_*.csv"  
echo "✅ Baseline CPU intensive load: baseline_cpu_intensive_mixed_*.csv"
echo ""
echo "🧮 MIXED WORKLOAD CHARACTERISTICS:"
echo "📈 Gateway: s0 (orchestration)"
echo "🧠 Memory: s1,s2 (50MB allocations)"
echo "💾 I/O: s3,s4 (disk operations)"
echo "⚡ CPU: s5 (π[800] computation, 2 trials)"
echo "🔄 Mixed: s6 (CPU+Memory hybrid)"
echo ""
echo "🔍 Expected energy patterns:"
echo "   CPU services > Memory services > I/O services > Gateway"
