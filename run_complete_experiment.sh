#!/bin/bash

# Energy-Aware Autoscaling Phase 1 Experiment Script
# Total runtime: ~8 minutes
# This script runs baseline data collection only

set -e  # Exit on any error

echo "🚀 ENERGY-AWARE AUTOSCALING PHASE 1 EXPERIMENT"
echo "=============================================="
echo "⏰ Start time: $(date)"
echo "📅 Experiment date: $(date +%Y-%m-%d)"
echo "🕐 Estimated total time: 8 minutes"
echo "=============================================="

# Configuration
GATEWAY_URL="http://192.168.49.2:31113"
EXPERIMENT_START_TIME=$(date +%Y%m%d_%H%M%S)
LOG_FILE="experiment_log_${EXPERIMENT_START_TIME}.txt"

# Function to log with timestamp
log_action() {
    local message="$1"
    local timestamp=$(date '+%H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# Function to wait and show countdown
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

# Function to check if services are running
check_services() {
    log_action "🔍 Checking if muBench services are running..."
    if ! kubectl get pods | grep -q "s0"; then
        log_action "❌ ERROR: muBench services not found! Please deploy muBench first."
        exit 1
    fi
    log_action "✅ muBench services are running"
}

# Function to cleanup any existing HPAs
cleanup_hpas() {
    log_action "🧹 Removing any existing HPAs..."
    kubectl delete hpa --all --ignore-not-found=true
    wait_with_countdown 30 "HPA cleanup"
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

# Phase 1: Baseline Data Collection (8 minutes)
run_phase1_baseline() {
    log_action "🔬 PHASE 1: Baseline Data Collection (8 minutes)"
    log_action "==============================================="
    
    cleanup_hpas
    
    # Baseline without load (2 minutes)
    log_action "📊 Collecting baseline metrics (no load) - 2 minutes..."
    python3 research_data_collector.py --mode baseline --duration 2 &
    BASELINE_PID=$!
    wait $BASELINE_PID
    
    # Baseline with light load (6 minutes total: 1 min warmup + 5 min collection)
    log_action "📊 Starting light load and collecting metrics - 6 minutes..."
    python3 load_tester.py --gateway "$GATEWAY_URL" --workload constant --rps 2 --duration 360 &
    LOAD_PID=$!
    
    wait_with_countdown 60 "load warmup"
    python3 research_data_collector.py --mode experiment --scenario baseline_constant_load --duration 5 &
    COLLECT_PID=$!
    
    wait $COLLECT_PID
    wait $LOAD_PID
    
    log_action "✅ Phase 1 completed"
}

# Phase 2: CPU-based HPA Testing (24 minutes)
run_phase2_cpu_hpa() {
    log_action "⚙️ PHASE 2: CPU-based HPA Testing (24 minutes)"
    log_action "=============================================="
    
    # Deploy CPU-based HPA
    log_action "🔧 Deploying CPU-based HPA..."
    cat > /tmp/cpu-hpa.yaml << EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: cpu-hpa-s0
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: s0
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
EOF
    
    kubectl apply -f /tmp/cpu-hpa.yaml
    wait_with_countdown 30 "HPA initialization"
    
    # Test 1: Constant Medium Load (8 minutes: 1 min warmup + 6 min collection + 1 min cooldown)
    log_action "🧪 Test 1: CPU HPA - Constant Medium Load (8 minutes)..."
    python3 load_tester.py --gateway "$GATEWAY_URL" --workload constant --rps 6 --duration 420 &
    LOAD_PID=$!
    
    wait_with_countdown 60 "load warmup"
    python3 research_data_collector.py --mode experiment --scenario cpu_hpa_constant_medium --duration 6 &
    COLLECT_PID=$!
    
    wait $COLLECT_PID
    wait $LOAD_PID
    wait_with_countdown 60 "cooldown"
    
    # Test 2: Burst Load (8 minutes: 1 min warmup + 6 min collection + 1 min cooldown)
    log_action "🧪 Test 2: CPU HPA - Burst Load (8 minutes)..."
    python3 load_tester.py --gateway "$GATEWAY_URL" --workload burst --rps 10 --duration 420 &
    LOAD_PID=$!
    
    wait_with_countdown 60 "load warmup"
    python3 research_data_collector.py --mode experiment --scenario cpu_hpa_burst --duration 6 &
    COLLECT_PID=$!
    
    wait $COLLECT_PID
    wait $LOAD_PID
    wait_with_countdown 60 "cooldown"
    
    # Test 3: CPU Intensive Load (8 minutes: 1 min warmup + 6 min collection + 1 min cooldown)
    log_action "🧪 Test 3: CPU HPA - CPU Intensive Load (8 minutes)..."
    python3 load_tester.py --gateway "$GATEWAY_URL" --workload cpu_intensive --rps 4 --duration 420 &
    LOAD_PID=$!
    
    wait_with_countdown 60 "load warmup"
    python3 research_data_collector.py --mode experiment --scenario cpu_hpa_cpu_intensive --duration 6 &
    COLLECT_PID=$!
    
    wait $COLLECT_PID
    wait $LOAD_PID
    wait_with_countdown 60 "cooldown"
    
    log_action "✅ Phase 2 completed"
}

# Phase 3: Energy-Aware HPA Testing (24 minutes)
run_phase3_energy_hpa() {
    log_action "🔋 PHASE 3: Energy-Aware HPA Testing (24 minutes)"
    log_action "==============================================="
    
    # Switch to Energy-Aware HPA
    log_action "🔧 Switching to Energy-Aware HPA..."
    kubectl delete hpa --all --ignore-not-found=true
    wait_with_countdown 30 "HPA cleanup"
    
    if [ -f "energy-aware-hpa.yaml" ]; then
        kubectl apply -f energy-aware-hpa.yaml
        wait_with_countdown 60 "Energy-Aware HPA initialization"
    else
        log_action "⚠️  WARNING: energy-aware-hpa.yaml not found, continuing without Energy-Aware HPA"
    fi
    
    # Test 1: Constant Medium Load (8 minutes: 1 min warmup + 6 min collection + 1 min cooldown)
    log_action "🧪 Test 1: Energy HPA - Constant Medium Load (8 minutes)..."
    python3 load_tester.py --gateway "$GATEWAY_URL" --workload constant --rps 6 --duration 420 &
    LOAD_PID=$!
    
    wait_with_countdown 60 "load warmup"
    python3 research_data_collector.py --mode experiment --scenario energy_hpa_constant_medium --duration 6 &
    COLLECT_PID=$!
    
    wait $COLLECT_PID
    wait $LOAD_PID
    wait_with_countdown 60 "cooldown"
    
    # Test 2: Burst Load (8 minutes: 1 min warmup + 6 min collection + 1 min cooldown)
    log_action "🧪 Test 2: Energy HPA - Burst Load (8 minutes)..."
    python3 load_tester.py --gateway "$GATEWAY_URL" --workload burst --rps 10 --duration 420 &
    LOAD_PID=$!
    
    wait_with_countdown 60 "load warmup"
    python3 research_data_collector.py --mode experiment --scenario energy_hpa_burst --duration 6 &
    COLLECT_PID=$!
    
    wait $COLLECT_PID
    wait $LOAD_PID
    wait_with_countdown 60 "cooldown"
    
    # Test 3: CPU Intensive Load (8 minutes: 1 min warmup + 6 min collection + 1 min cooldown)
    log_action "🧪 Test 3: Energy HPA - CPU Intensive Load (8 minutes)..."
    python3 load_tester.py --gateway "$GATEWAY_URL" --workload cpu_intensive --rps 4 --duration 420 &
    LOAD_PID=$!
    
    wait_with_countdown 60 "load warmup"
    python3 research_data_collector.py --mode experiment --scenario energy_hpa_cpu_intensive --duration 6 &
    COLLECT_PID=$!
    
    wait $COLLECT_PID
    wait $LOAD_PID
    wait_with_countdown 60 "cooldown"
    
    log_action "✅ Phase 3 completed"
}

# Phase 4: Data Analysis and Reporting (4 minutes)
run_phase4_analysis() {
    log_action "📊 PHASE 4: Data Analysis and Reporting (4 minutes)"
    log_action "=================================================="
    
    log_action "📋 Generating comprehensive analysis..."
    python3 research_data_collector.py --mode summary
    
    log_action "📁 Listing collected data files..."
    ls -la research_data/
    
    log_action "📄 Data files summary:"
    echo "----------------------------------------"
    find research_data/ -name "*.csv" -exec basename {} \; | sort
    echo "----------------------------------------"
    find research_data/ -name "*.json" -exec basename {} \; | sort
    
    log_action "✅ Phase 4 completed"
}

# Main execution
main() {
    # Prerequisites check
    log_action "🔍 Running prerequisites check..."
    check_services
    check_gateway
    
    # Record start time
    EXPERIMENT_START=$(date +%s)
    
    # Run only Phase 1
    run_phase1_baseline    # 8 minutes
    
    # Calculate total time
    EXPERIMENT_END=$(date +%s)
    TOTAL_TIME=$((EXPERIMENT_END - EXPERIMENT_START))
    TOTAL_MINUTES=$((TOTAL_TIME / 60))
    
    log_action "🎉 PHASE 1 COMPLETED SUCCESSFULLY!"
    log_action "============================================"
    log_action "⏰ End time: $(date)"
    log_action "🕐 Total duration: ${TOTAL_MINUTES} minutes (${TOTAL_TIME} seconds)"
    log_action "📁 Results directory: research_data/"
    log_action "📄 Experiment log: $LOG_FILE"
    log_action "============================================"
    
    echo ""
    echo "📊 BASELINE DATA SUMMARY:"
    echo "========================"
    echo "📁 Baseline data files are in: research_data/"
    echo "🔬 Baseline metrics: baseline_*.csv"
    echo " Complete log: $LOG_FILE"
    echo ""
    echo "🎯 Next steps:"
    echo "1. Review baseline data in research_data/"
    echo "2. Run Phase 2 (CPU HPA) experiments"
    echo "3. Run Phase 3 (Energy-Aware HPA) experiments"
}

# Handle script interruption
trap 'echo "🛑 Experiment interrupted! Check $LOG_FILE for details."; exit 1' INT TERM

# Run the experiment
main "$@"
