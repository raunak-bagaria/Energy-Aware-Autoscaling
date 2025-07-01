#!/bin/bash

# Phase 2: CPU-based HPA Testing Script
# This script implements Phase 2 exactly like Phase 1 data collection

set -e  # Exit on any error

echo "⚙️ PHASE 2: CPU-based HPA Testing"
echo "=================================="
echo "⏰ Start time: $(date)"
echo "🎯 Goal: Test CPU-based autoscaling and collect data"
echo "=================================="

# Configuration
GATEWAY_URL="http://192.168.49.2:31113"
EXPERIMENT_START_TIME=$(date +%Y%m%d_%H%M%S)
LOG_FILE="phase2_log_${EXPERIMENT_START_TIME}.txt"

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

# Step 1: Clean up any existing HPAs
log_action "🧹 Step 1: Cleaning up existing HPAs..."
kubectl delete hpa --all --ignore-not-found=true
wait_with_countdown 30 "HPA cleanup"

# Step 2: Generate and deploy CPU-based HPAs for all services
log_action "🔧 Step 2: Generating CPU-based HPAs for all microservices..."

# Create output directory for HPAs
mkdir -p /tmp/generated-hpas

# Generate HPAs using muBench's HPA generator
cd /root/muBench/Add-on/HPA
log_action "📝 Running HPA generator..."
python3 create-hpa.py --in /root/muBench/SimulationWorkspace/yamls --out /tmp/generated-hpas --template hpa-template.yaml

# Apply all generated HPAs
log_action "🚀 Applying HPAs for all services..."
kubectl apply -f /tmp/generated-hpas/

# Verify HPAs are created
log_action "✅ Verifying HPA deployment..."
kubectl get hpa | tee -a "$LOG_FILE"

# Return to experiment directory
cd /home/ccbd/autoscaling/muBench/Energy-Aware-Autoscaling

wait_with_countdown 60 "HPA initialization and metrics server sync"

# Step 3: Test 1 - CPU HPA with Constant Medium Load (matching Phase 1 approach)
log_action "🧪 Step 3: Test 1 - CPU HPA with Constant Medium Load..."
log_action "📊 Starting load generation and data collection..."

# Start load test in background (same pattern as Phase 1 baseline)
python3 load_tester.py --gateway "$GATEWAY_URL" --workload constant --rps 6 --duration 600 &
LOAD_PID=$!

# Wait for load to stabilize (same as Phase 1)
wait_with_countdown 60 "load warmup and stabilization"

# Collect data for 8 minutes (matching Phase 1 duration)
log_action "📈 Collecting CPU HPA data for 8 minutes..."
python3 research_data_collector.py --mode experiment --scenario cpu_hpa_constant_medium --duration 8 &
COLLECT_PID=$!

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ Data collection completed"

# Wait for load test to finish
wait $LOAD_PID
log_action "✅ Load test completed"

# Cool down period
wait_with_countdown 120 "system cooldown"

# Step 4: Test 2 - CPU HPA with Burst Load
log_action "🧪 Step 4: Test 2 - CPU HPA with Burst Load..."

# Start burst load test
python3 load_tester.py --gateway "$GATEWAY_URL" --workload burst --rps 10 --duration 600 &
LOAD_PID=$!

# Wait for load to stabilize
wait_with_countdown 60 "burst load warmup"

# Collect data for 8 minutes
log_action "📈 Collecting CPU HPA burst data for 8 minutes..."
python3 research_data_collector.py --mode experiment --scenario cpu_hpa_burst --duration 8 &
COLLECT_PID=$!

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ Burst data collection completed"

# Wait for load test to finish
wait $LOAD_PID
log_action "✅ Burst load test completed"

# Cool down period
wait_with_countdown 120 "system cooldown"

# Step 5: Test 3 - CPU HPA with CPU Intensive Load
log_action "🧪 Step 5: Test 3 - CPU HPA with CPU Intensive Load..."

# Start CPU intensive load test
python3 load_tester.py --gateway "$GATEWAY_URL" --workload cpu_intensive --rps 5 --duration 600 &
LOAD_PID=$!

# Wait for load to stabilize
wait_with_countdown 60 "CPU intensive load warmup"

# Collect data for 8 minutes
log_action "📈 Collecting CPU HPA intensive data for 8 minutes..."
python3 research_data_collector.py --mode experiment --scenario cpu_hpa_cpu_intensive --duration 8 &
COLLECT_PID=$!

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ CPU intensive data collection completed"

# Wait for load test to finish
wait $LOAD_PID
log_action "✅ CPU intensive load test completed"

# Step 6: Show results
log_action "📊 Step 6: Phase 2 Results Summary"
log_action "=================================="

# Check HPA status after all tests
log_action "🔍 Final HPA status:"
kubectl get hpa | tee -a "$LOG_FILE"

# List generated data files
log_action "📁 Generated data files:"
ls -la research_data/cpu_hpa_* | tee -a "$LOG_FILE"

# Calculate total time
EXPERIMENT_END=$(date +%s)
if [ -n "$EXPERIMENT_START" ]; then
    TOTAL_TIME=$((EXPERIMENT_END - EXPERIMENT_START))
    TOTAL_MINUTES=$((TOTAL_TIME / 60))
    log_action "⏰ Total Phase 2 duration: ${TOTAL_MINUTES} minutes"
fi

log_action "🎉 PHASE 2 COMPLETED SUCCESSFULLY!"
log_action "=================================="
log_action "⏰ End time: $(date)"
log_action "📁 Results in: research_data/"
log_action "📄 Log file: $LOG_FILE"

echo ""
echo "📊 PHASE 2 DATA SUMMARY:"
echo "========================"
echo "✅ CPU HPA constant medium load: cpu_hpa_constant_medium_*.csv"
echo "✅ CPU HPA burst load: cpu_hpa_burst_*.csv"  
echo "✅ CPU HPA CPU intensive load: cpu_hpa_cpu_intensive_*.csv"
echo ""
echo "🔍 You can now compare these with your Phase 1 baseline data!"
echo "📋 Next: Run Phase 3 (Energy-Aware HPA) for complete comparison"
