 
#!/bin/bash

# Phase 3: Energy-Aware Autoscaling Testing Script
# This script implements Phase 3 with custom energy-aware autoscaling

set -e  # Exit on any error

echo "⚡ PHASE 3: Energy-Aware Autoscaling Testing"
echo "============================================="
echo "⏰ Start time: $(date)"
echo "🎯 Goal: Test energy-aware autoscaling and collect data"
echo "============================================="

# Configuration
GATEWAY_URL="http://192.168.49.2:31113"
PROMETHEUS_URL="http://192.168.49.2:30000"
EXPERIMENT_START_TIME=$(date +%Y%m%d_%H%M%S)
LOG_FILE="phase3_log_${EXPERIMENT_START_TIME}.txt"
NAMESPACE="default"
SERVICES=("s0" "s1" "s2" "s3" "s4" "s5" "s6" "s7" "s8" "s9")


# Energy-Aware Autoscaling Parameters
LOW_EFFICIENCY_THRESHOLD=0.15   # Scale UP when efficiency < 0.15 (more conservative)
HIGH_EFFICIENCY_THRESHOLD=0.4   # Scale DOWN when efficiency > 0.4 (more conservative)
MIN_REPLICAS=1
MAX_REPLICAS=4                  # Reduced from 5 to 4
AUTOSCALER_INTERVAL=60
RPS_SCALE_DOWN_THRESHOLD=1.0    # Scale DOWN when RPS < 1.0 (reduced from 2.0)
MAX_SYSTEM_POWER=70             # System-wide power budget (Watts)
SCALE_COOLDOWN=180              # Cooldown period between scaling actions per service (seconds)
EPR_MARGIN=1.5                  # Wider margin to reduce oscillations

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

# Function to query Prometheus
query_prometheus() {
    local query="$1"
    curl -s -G "${PROMETHEUS_URL}/api/v1/query" --data-urlencode "query=${query}" | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for result in data['data']['result']:
        print(f\"{result['metric']}:{result['value'][1]}\")
except:
    pass
" 2>/dev/null || echo ""
}

# Function to get current replicas
get_current_replicas() {
    local service="$1"
    kubectl get deployment "$service" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1"
}

# Function to scale deployment
scale_deployment() {
    local service="$1"
    local replicas="$2"
    log_action "🔧 Scaling $service to $replicas replicas"
    kubectl scale deployment "$service" --replicas="$replicas" -n "$NAMESPACE"
}

# Function to create embedded Python autoscaler with real Kepler integration
# Add these improvements to your create_python_autoscaler() function:

create_python_autoscaler() {
    cat > energy_autoscaler_embedded.py << 'EOF'
#!/usr/bin/env python3
"""
Enhanced Energy-Aware Autoscaler with Dynamic Thresholds and Moving Averages
"""

import time
import subprocess
import json
import requests
import random
import sys
import re
from datetime import datetime
from collections import deque
import statistics

# Configuration from bash script
LOW_EFFICIENCY_THRESHOLD = 0.15
HIGH_EFFICIENCY_THRESHOLD = 0.4
MIN_REPLICAS = 1
MAX_REPLICAS = 4
RPS_SCALE_DOWN_THRESHOLD = 1.0
AUTOSCALER_INTERVAL = 60
PROMETHEUS_URL = "http://192.168.49.2:30000"
NAMESPACE = "default"
SERVICES = ["s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9"]
MAX_SYSTEM_POWER = 70
SCALE_COOLDOWN = 180
EPR_MARGIN = 1.5

# NEW: Dynamic baseline management
METRIC_WINDOW = 5  # Moving average window
WORKLOAD_BASELINES = {
    "cpu_intensive": {"epr": 8.0, "efficiency": 0.25},
    "burst": {"epr": 6.0, "efficiency": 0.15},
    "constant": {"epr": 5.0, "efficiency": 0.20},
    "default": {"epr": 7.0, "efficiency": 0.18}
}

# Current workload type (can be set dynamically)
CURRENT_WORKLOAD = "cpu_intensive"  # This could be passed as parameter

# Enhanced history tracking
EPR_HISTORY = {service: deque(maxlen=METRIC_WINDOW) for service in SERVICES}
EFFICIENCY_HISTORY = {service: deque(maxlen=METRIC_WINDOW) for service in SERVICES}
GLOBAL_EPR_HISTORY = deque(maxlen=METRIC_WINDOW)
GLOBAL_EFFICIENCY_HISTORY = deque(maxlen=METRIC_WINDOW)

# System-wide metrics history for trend analysis
SYSTEM_METRICS_HISTORY = deque(maxlen=10)

# Scaling cooldown tracking
LAST_SCALE_TIME = {}

def log_action(message):
    timestamp = datetime.now().strftime('%H:%M:%S')
    print(f"[{timestamp}] {message}", flush=True)

def log_check(message):
    """Log to check.txt file to track data sources"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    with open('check.txt', 'a') as f:
        f.write(f"[{timestamp}] {message}\n")

def calculate_moving_average(data_deque):
    """Calculate moving average from deque"""
    if len(data_deque) == 0:
        return 0
    return statistics.mean(data_deque)

def calculate_adaptive_thresholds(global_metrics):
    """Calculate adaptive thresholds based on current workload and system state"""
    baseline = WORKLOAD_BASELINES.get(CURRENT_WORKLOAD, WORKLOAD_BASELINES["default"])

    # Get current system averages
    avg_epr = calculate_moving_average(GLOBAL_EPR_HISTORY)
    avg_efficiency = calculate_moving_average(GLOBAL_EFFICIENCY_HISTORY)

    # Adaptive threshold calculation
    if avg_epr > 0:
        # Use actual system performance to adjust thresholds
        epr_upper = max(avg_epr * 1.3, baseline["epr"] * 1.2)  # Scale up threshold
        epr_lower = min(avg_epr * 0.7, baseline["epr"] * 0.8)  # Scale down threshold
    else:
        # Fallback to baseline thresholds
        epr_upper = baseline["epr"] * 1.2
        epr_lower = baseline["epr"] * 0.8

    if avg_efficiency > 0:
        # Efficiency thresholds (higher is better)
        eff_lower = max(avg_efficiency * 0.7, baseline["efficiency"] * 0.7)  # Scale up threshold
        eff_upper = min(avg_efficiency * 1.3, baseline["efficiency"] * 1.3)  # Scale down threshold
    else:
        eff_lower = baseline["efficiency"] * 0.7
        eff_upper = baseline["efficiency"] * 1.3

    return {
        "epr_upper": epr_upper,
        "epr_lower": epr_lower,
        "efficiency_lower": eff_lower,
        "efficiency_upper": eff_upper
    }

def detect_workload_pattern():
    """Detect current workload pattern from system metrics"""
    if len(SYSTEM_METRICS_HISTORY) < 3:
        return CURRENT_WORKLOAD

    recent_metrics = list(SYSTEM_METRICS_HISTORY)[-3:]

    # Calculate variance in RPS and power to detect pattern
    rps_values = [m['total_rps'] for m in recent_metrics]
    power_values = [m['total_power'] for m in recent_metrics]

    rps_variance = statistics.variance(rps_values) if len(rps_values) > 1 else 0
    power_variance = statistics.variance(power_values) if len(power_values) > 1 else 0

    # Pattern detection logic
    if rps_variance > 2.0:  # High RPS variance
        return "burst"
    elif power_variance > 5.0:  # High power variance
        return "cpu_intensive"
    else:
        return "constant"

def get_current_replicas(service):
    try:
        result = subprocess.run(
            ["kubectl", "get", "deployment", service, "-n", NAMESPACE, "-o", "jsonpath={.spec.replicas}"],
            capture_output=True, text=True, check=True
        )
        return int(result.stdout.strip()) if result.stdout.strip() else 1
    except:
        return 1

def scale_deployment(service, replicas):
    log_action(f"🔧 Scaling {service} to {replicas} replicas")
    try:
        subprocess.run(
            ["kubectl", "scale", "deployment", service, f"--replicas={replicas}", "-n", NAMESPACE],
            check=True
        )
        time.sleep(5)
        return True
    except Exception as e:
        log_action(f"❌ Failed to scale {service}: {e}")
        return False

def query_prometheus(query):
    """Query Prometheus and return results"""
    try:
        response = requests.get(f"{PROMETHEUS_URL}/api/v1/query",
                              params={"query": query}, timeout=10)
        if response.status_code == 200:
            result = response.json()
            if result.get('status') == 'success':
                return result
        return None
    except Exception as e:
        log_action(f"❌ Prometheus connection error: {e}")
        return None

def extract_service_name(pod_name):
    """Extract service name from pod name"""
    match = re.match(r'(s[0-9]+)', pod_name)
    return match.group(1) if match else None

def get_real_service_metrics():
    """Get real metrics with enhanced processing"""
    metrics = {}

    # Queries for real measurements
    replica_query = 'kube_deployment_status_replicas{deployment=~"s[0-9]+"}'
    power_query = 'rate(kepler_container_joules_total{container_namespace="default"}[5m])'
    rps_query = 'rate(mub_request_processing_latency_milliseconds_count{kubernetes_service=~"s[0-9]+"}[5m])'

    log_check("=== ENHANCED AUTOSCALER ITERATION START ===")

    # Query Prometheus
    replica_data = query_prometheus(replica_query)
    power_data = query_prometheus(power_query)
    rps_data = query_prometheus(rps_query)

    # Process replica data
    if replica_data and replica_data.get('data', {}).get('result'):
        for metric in replica_data['data']['result']:
            service = metric['metric']['deployment']
            if service not in metrics:
                metrics[service] = {}
            metrics[service]['replicas'] = int(metric['value'][1])

    # Process power data
    if power_data and power_data.get('data', {}).get('result'):
        service_power = {}
        for metric in power_data['data']['result']:
            pod_name = metric['metric'].get('pod_name', '')
            service = extract_service_name(pod_name)
            if service:
                power_value = float(metric['value'][1])
                if power_value > 0:
                    if service not in service_power:
                        service_power[service] = []
                    service_power[service].append(power_value)

        for service, power_values in service_power.items():
            if service not in metrics:
                metrics[service] = {}
            metrics[service]['power_watts'] = sum(power_values)
            metrics[service]['power_source'] = 'kepler_measured'

    # Process RPS data
    if rps_data and rps_data.get('data', {}).get('result'):
        for metric in rps_data['data']['result']:
            service = metric['metric'].get('kubernetes_service', '')
            if service:
                if service not in metrics:
                    metrics[service] = {}
                rps_value = float(metric['value'][1])
                metrics[service]['rps'] = rps_value
                metrics[service]['rps_source'] = 'mubench_measured'

    # Fill missing services
    for service in SERVICES:
        if service not in metrics:
            metrics[service] = {'replicas': get_current_replicas(service)}

    # Calculate metrics with fallback estimation
    for service, m in metrics.items():
        rps = m.get('rps', 0)
        power = m.get('power_watts', 0)
        replicas = m.get('replicas', 1)

        # Enhanced power estimation
        if power == 0:
            if rps > 0:
                power = 2.0 + (rps * 0.8) if replicas == 1 else 1.0 * replicas + (rps * 0.3)
            else:
                power = 2.5 if replicas == 1 else 1.2 * replicas
            m['power_watts'] = power
            m['power_source'] = 'estimated'

        # Enhanced RPS estimation
        if rps == 0:
            if power > (1.5 * replicas):
                baseline_power = 1.2 * replicas
                excess_power = max(0, power - baseline_power)
                rps = excess_power / 0.5
            else:
                rps = random.uniform(0.1, 0.3) if replicas == 1 else random.uniform(0.5, 1.5) * replicas
            m['rps'] = rps
            m['rps_source'] = 'estimated'

        # Calculate efficiency metrics
        m['efficiency_rps_per_watt'] = rps / power if power > 0 else 0
        m['epr_joules_per_request'] = power / rps if rps > 0 else float('inf')

    return metrics

def enhanced_energy_aware_autoscale():
    """Enhanced autoscaling with adaptive thresholds and pattern detection"""
    global CURRENT_WORKLOAD

    log_action("🧠 Running ENHANCED energy-aware autoscaling with adaptive thresholds...")

    # Get metrics
    metrics = get_real_service_metrics()
    scaling_actions = 0
    current_time = time.time()

    # Calculate system-wide metrics
    total_power = sum(m.get('power_watts', 0) for m in metrics.values())
    total_rps = sum(m.get('rps', 0) for m in metrics.values())
    total_replicas = sum(m.get('replicas', 1) for m in metrics.values())

    global_epr = total_power / total_rps if total_rps > 0 else float('inf')
    global_efficiency = total_rps / total_power if total_power > 0 else 0

    # Update history
    GLOBAL_EPR_HISTORY.append(global_epr)
    GLOBAL_EFFICIENCY_HISTORY.append(global_efficiency)

    # Store system metrics for pattern detection
    SYSTEM_METRICS_HISTORY.append({
        'total_power': total_power,
        'total_rps': total_rps,
        'total_replicas': total_replicas,
        'timestamp': current_time
    })

    # Detect workload pattern and adapt
    detected_workload = detect_workload_pattern()
    if detected_workload != CURRENT_WORKLOAD:
        log_action(f"🔄 Workload pattern changed: {CURRENT_WORKLOAD} → {detected_workload}")
        CURRENT_WORKLOAD = detected_workload

    # Calculate adaptive thresholds
    thresholds = calculate_adaptive_thresholds({
        'total_power': total_power,
        'total_rps': total_rps,
        'global_epr': global_epr,
        'global_efficiency': global_efficiency
    })

    # Get smoothed averages
    smoothed_global_epr = calculate_moving_average(GLOBAL_EPR_HISTORY)
    smoothed_global_efficiency = calculate_moving_average(GLOBAL_EFFICIENCY_HISTORY)

    log_action(f"📊 Workload: {CURRENT_WORKLOAD} | Global EPR: {smoothed_global_epr:.3f} J/req | Efficiency: {smoothed_global_efficiency:.6f} RPS/W")
    log_action(f"📏 Adaptive Thresholds - EPR: ↑>{thresholds['epr_upper']:.2f}, ↓<{thresholds['epr_lower']:.2f}")
    log_action(f"🔋 System: {total_power:.2f}W/{MAX_SYSTEM_POWER}W, {total_rps:.2f} RPS, {total_replicas} replicas")

    log_action("=" * 110)
    log_action(f"{'Service':<8} {'Rep':<3} {'RPS':<7} {'Pow(W)':<7} {'EPR':<7} {'Eff':<7} {'EPR_MA':<7} {'Eff_MA':<7} {'Cool':<6} {'Decision':<15}")
    log_action("-" * 110)

    for service in SERVICES:
        if service not in metrics:
            continue

        m = metrics[service]
        rps = m.get('rps', 0)
        power = m.get('power_watts', 0)
        replicas = m.get('replicas', 1)
        epr = m.get('epr_joules_per_request', float('inf'))
        efficiency = m.get('efficiency_rps_per_watt', 0)

        # Update service-specific history
        EPR_HISTORY[service].append(epr)
        EFFICIENCY_HISTORY[service].append(efficiency)

        # Calculate moving averages
        epr_ma = calculate_moving_average(EPR_HISTORY[service])
        efficiency_ma = calculate_moving_average(EFFICIENCY_HISTORY[service])

        # Check cooldown
        last_scale = LAST_SCALE_TIME.get(service, 0)
        cooldown_remaining = max(0, SCALE_COOLDOWN - (current_time - last_scale))
        cooldown_status = f"{cooldown_remaining:.0f}s" if cooldown_remaining > 0 else "Ready"

        # Enhanced scaling logic with adaptive thresholds
        should_scale_up = (
            epr_ma > thresholds['epr_upper'] and
            efficiency_ma < thresholds['efficiency_lower'] and
            replicas < MAX_REPLICAS and
            power > 0.1
        )

        should_scale_down = (
            epr_ma < thresholds['epr_lower'] and
            efficiency_ma > thresholds['efficiency_upper'] and
            rps < RPS_SCALE_DOWN_THRESHOLD and
            replicas > MIN_REPLICAS
        )

        decision = "No scaling"

        # Apply scaling with all constraints
        if should_scale_up and cooldown_remaining == 0:
            if total_power <= MAX_SYSTEM_POWER:
                new_replicas = replicas + 1
                decision = f"Scale UP to {new_replicas}"
                log_action(f"⬆️  {service}: High EPR ({epr_ma:.2f}) + Low Eff ({efficiency_ma:.6f}) → Scale UP")
                if scale_deployment(service, new_replicas):
                    scaling_actions += 1
                    LAST_SCALE_TIME[service] = current_time
            else:
                decision = "Power budget hit"

        elif should_scale_down and cooldown_remaining == 0:
            new_replicas = replicas - 1
            decision = f"Scale DOWN to {new_replicas}"
            log_action(f"⬇️  {service}: Low EPR ({epr_ma:.2f}) + High Eff ({efficiency_ma:.6f}) → Scale DOWN")
            if scale_deployment(service, new_replicas):
                scaling_actions += 1
                LAST_SCALE_TIME[service] = current_time

        elif cooldown_remaining > 0:
            decision = f"Cooldown {cooldown_remaining:.0f}s"
        else:
            decision = "Optimal"

        # Format display values
        epr_display = f"{epr:.2f}" if epr < 999 else "999+"
        epr_ma_display = f"{epr_ma:.2f}" if epr_ma < 999 else "999+"

        log_action(f"{service:<8} {replicas:<3} {rps:<7.2f} {power:<7.2f} {epr_display:<7} {efficiency:<7.4f} {epr_ma_display:<7} {efficiency_ma:<7.4f} {cooldown_status:<6} {decision:<15}")

    log_action("=" * 110)
    log_action(f"🎯 Enhanced autoscaling completed: {scaling_actions} actions | Workload: {CURRENT_WORKLOAD}")
    log_action(f"📊 System: {total_power:.2f}W, {total_rps:.2f} RPS, EPR: {smoothed_global_epr:.3f} J/req")

def main():
    log_action("🚀 ENHANCED Energy-Aware Autoscaler with Adaptive Thresholds")
    log_action(f"🔧 Workload: {CURRENT_WORKLOAD} | Window: {METRIC_WINDOW} | Budget: {MAX_SYSTEM_POWER}W")

    with open('check.txt', 'w') as f:
        f.write(f"Enhanced Energy-Aware Autoscaler with Adaptive Thresholds\n")
        f.write(f"Started: {datetime.now()}\n")
        f.write(f"Features: Moving averages, adaptive thresholds, pattern detection\n")
        f.write("="*80 + "\n")

    try:
        iteration = 1
        while True:
            log_action(f"🔄 Enhanced autoscaling iteration {iteration}")
            enhanced_energy_aware_autoscale()
            time.sleep(AUTOSCALER_INTERVAL)
            iteration += 1
    except KeyboardInterrupt:
        log_action("🛑 Enhanced autoscaler stopped")
    except Exception as e:
        log_action(f"❌ Autoscaler error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF
}
# Function to run embedded Python autoscaler
run_energy_aware_autoscaler() {
    log_action "🤖 Creating and starting embedded Python autoscaler..."

    # Create the Python autoscaler file
    create_python_autoscaler

    # Start the Python autoscaler in background
    python3 energy_autoscaler_embedded.py &
    AUTOSCALER_PID=$!

    log_action "🚀 Energy-aware autoscaler started with PID: $AUTOSCALER_PID"
}

# Function to stop autoscaler
stop_energy_aware_autoscaler() {
    if [[ -n "$AUTOSCALER_PID" ]]; then
        log_action "🛑 Stopping energy-aware autoscaler (PID: $AUTOSCALER_PID)"
        kill "$AUTOSCALER_PID" 2>/dev/null || true
        wait "$AUTOSCALER_PID" 2>/dev/null || true
    fi
}

# Trap to ensure autoscaler is stopped on script exit
trap stop_energy_aware_autoscaler EXIT

# Step 1: Clean up any existing HPAs (energy-aware uses custom scaling)
log_action "🧹 Step 1: Cleaning up existing HPAs (energy-aware uses custom scaling)..."
kubectl delete hpa --all --ignore-not-found=true
wait_with_countdown 30 "HPA cleanup"

# Step 2: Reset all services to 1 replica for consistent starting point
log_action "🔄 Step 2: Resetting all services to 1 replica..."
for service in "${SERVICES[@]}"; do
    scale_deployment "$service" 1
done
wait_with_countdown 60 "service reset and stabilization"

# Step 3: Start energy-aware autoscaler
run_energy_aware_autoscaler
wait_with_countdown 120 "autoscaler initialization and baseline metrics"

# Step 4: Test 1 - Energy-Aware with Constant Medium Load
log_action "🧪 Step 4: Test 1 - Energy-Aware with Constant Medium Load..."
log_action "📊 Starting load generation and data collection with energy-aware autoscaling..."

# Start load test in background
python3 load_tester.py --gateway "$GATEWAY_URL" --workload constant --rps 6 --duration 600 &
LOAD_PID=$!

# Wait for load to stabilize
wait_with_countdown 60 "load warmup and autoscaler adaptation"

# Collect data for 8 minutes
log_action "📈 Collecting energy-aware autoscaling data for 8 minutes..."
python3 research_data_collector.py --mode experiment --scenario energy_aware_constant_medium --duration 8 &
COLLECT_PID=$!

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ Data collection completed"

# Wait for load test to finish
wait $LOAD_PID
log_action "✅ Load test completed"

# Cool down period
wait_with_countdown 180 "system cooldown and autoscaler stabilization"

# Step 5: Test 2 - Energy-Aware with Burst Load
log_action "🧪 Step 5: Test 2 - Energy-Aware with Burst Load..."

# Start burst load test
python3 load_tester.py --gateway "$GATEWAY_URL" --workload burst --rps 10 --duration 600 &
LOAD_PID=$!

# Wait for load to stabilize
wait_with_countdown 60 "burst load warmup and autoscaler adaptation"

# Collect data for 8 minutes
log_action "📈 Collecting energy-aware burst data for 8 minutes..."
python3 research_data_collector.py --mode experiment --scenario energy_aware_burst --duration 8 &
COLLECT_PID=$!

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ Burst data collection completed"

# Wait for load test to finish
wait $LOAD_PID
log_action "✅ Burst load test completed"

# Cool down period
wait_with_countdown 180 "system cooldown and autoscaler stabilization"

# Step 6: Test 3 - Energy-Aware with CPU Intensive Load
log_action "🧪 Step 6: Test 3 - Energy-Aware with CPU Intensive Load..."

# Start CPU intensive load test
python3 load_tester.py --gateway "$GATEWAY_URL" --workload cpu_intensive --rps 5 --duration 600 &
LOAD_PID=$!

# Wait for load to stabilize
wait_with_countdown 60 "CPU intensive load warmup and autoscaler adaptation"

# Collect data for 8 minutes
log_action "📈 Collecting energy-aware CPU intensive data for 8 minutes..."
python3 research_data_collector.py --mode experiment --scenario energy_aware_cpu_intensive --duration 8 &
COLLECT_PID=$!

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ CPU intensive data collection completed"

# Wait for load test to finish
wait $LOAD_PID
log_action "✅ CPU intensive load test completed"

# Step 7: Stop autoscaler and show results
stop_energy_aware_autoscaler

log_action "📊 Step 7: Phase 3 Results Summary"
log_action "=================================="

# Show final replica counts
log_action "🔍 Final replica counts after energy-aware autoscaling:"
for service in "${SERVICES[@]}"; do
    replicas=$(get_current_replicas "$service")
    log_action "  $service: $replicas replicas"
done

# List generated data files
log_action "📁 Generated data files:"
ls -la research_data/energy_aware_* 2>/dev/null | tee -a "$LOG_FILE" || log_action "No energy_aware data files found yet"

log_action "🎉 PHASE 3 COMPLETED SUCCESSFULLY!"
log_action "=================================="
log_action "⏰ End time: $(date)"
log_action "📁 Results in: research_data/"
log_action "📄 Log file: $LOG_FILE"

echo ""
echo "⚡ PHASE 3 DATA SUMMARY:"
echo "========================"
echo "✅ Energy-aware constant medium load: energy_aware_constant_medium_*.csv"
echo "✅ Energy-aware burst load: energy_aware_burst_*.csv"
echo "✅ Energy-aware CPU intensive load: energy_aware_cpu_intensive_*.csv"
echo ""
echo "🔬 RESEARCH COMPARISON READY:"
echo "📊 Phase 1 (Baseline): No autoscaling"
echo "📊 Phase 2 (CPU HPA): Traditional CPU-based autoscaling (60% threshold)"
echo "📊 Phase 3 (Energy-Aware): Custom efficiency-based autoscaling (RPS/Watt)"
echo ""
echo "🔍 Compare EPR, power consumption, and efficiency across all three phases!"
echo "📋 Analysis: Energy-aware should show better EPR and fewer scaling events"
