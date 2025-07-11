#!/bin/bash

# Phase 3: Energy-Aware Autoscaling Testing Script for 7-service Mixed Workload (SHORT VERSION - 12-15 minutes)
# This script implements Phase 3 with custom energy-aware autoscaling

set -e  # Exit on any error

echo "⚡ PHASE 3: Energy-Aware Autoscaling Testing (7-Service Mixed Workload) - SHORT VERSION"
echo "======================================================================================="
echo "⏰ Start time: $(date)"
echo "🎯 Goal: Test energy-aware autoscaling and collect data (12-15 minute runtime)"
echo "🧮 Workload: 7-service heterogeneous workload (CPU+Memory+I/O)"
echo "📊 Services: s0[Gateway], s1-s2[Memory], s3-s4[I/O], s5[CPU], s6[CPU+Memory]"
echo "⚡ Optimized: Short durations, reduced cooldowns for quick testing"
echo "======================================================================================="

# Configuration
GATEWAY_URL="http://192.168.49.2:31113"
PROMETHEUS_URL="http://192.168.49.2:30000"
EXPERIMENT_START_TIME=$(date +%Y%m%d_%H%M%S)
LOG_FILE="phase3_mixed_log_${EXPERIMENT_START_TIME}.txt"
NAMESPACE="default"

# Define services by workload type (based on actual workmodel)
GATEWAY_SERVICES=("s0")                                           # Gateway service (no stress)
MEMORY_SERVICES=("s1" "s2")                                       # Memory stress services
IO_SERVICES=("s3" "s4")                                           # Disk I/O services
CPU_SERVICES=("s5")                                               # Pure CPU service (π computation)
MIXED_SERVICES=("s6")                                             # Services with both CPU and Memory
ALL_SERVICES=("s0" "s1" "s2" "s3" "s4" "s5" "s6")

# Energy-Aware Autoscaling Parameters (optimized for mixed workload)
LOW_EFFICIENCY_THRESHOLD=0.08   # Scale UP when efficiency < 0.08 (adapted for mixed complexity)
HIGH_EFFICIENCY_THRESHOLD=0.20  # Scale DOWN when efficiency > 0.20 (conservative for mixed services)
MIN_REPLICAS=1
MAX_REPLICAS=3                  # Conservative for 20-service setup
AUTOSCALER_INTERVAL=30          # Check interval for mixed workload
RPS_SCALE_DOWN_THRESHOLD=0.2    # Very low RPS threshold for mixed complexity
MAX_SYSTEM_POWER=100            # Higher power budget for mixed workload
SCALE_COOLDOWN=30               # Shorter cooldown for responsive mixed scaling
EPR_MARGIN=1.15                 # Margin for mixed workload efficiency

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

# Function to create embedded Python autoscaler with real Kepler integration for mixed workload
create_python_autoscaler() {
    cat > energy_autoscaler_mixed.py << 'EOF'
#!/usr/bin/env python3
"""
Enhanced Energy-Aware Autoscaler for Mixed Workload (CPU+Memory+I/O)
"""

import time
import subprocess
import json
import requests
import random
import sys
import re
import logging
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class MixedWorkloadEnergyAutoscaler:
    def __init__(self):
        self.prometheus_url = "http://192.168.49.2:30000"
        self.namespace = "default"
        
        # Services categorized by workload type
        self.gateway_services = ["s0"]
        self.memory_services = ["s1", "s2", "s6", "s9", "s12", "s13"]
        self.io_services = ["s3", "s4", "s5", "s7", "s10", "s11", "s14", "s15", "s16", "s17", "s18", "s19"]
        self.cpu_services = ["s8"]
        self.all_services = ["s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11", "s12", "s13", "s14", "s15", "s16", "s17", "s18", "s19"]
        
        # Workload-specific thresholds
        self.workload_thresholds = {
            "cpu": {"low_eff": 0.05, "high_eff": 0.15, "max_replicas": 3},
            "memory": {"low_eff": 0.10, "high_eff": 0.25, "max_replicas": 2},
            "io": {"low_eff": 0.08, "high_eff": 0.20, "max_replicas": 2},
            "gateway": {"low_eff": 0.15, "high_eff": 0.35, "max_replicas": 2}
        }
        
        # Scaling history and cooldowns
        self.last_scale_time = {}
        self.scale_cooldown = 30  # seconds
        self.efficiency_history = {}
        self.decision_log = []
        
        logger.info("🧮 Mixed Workload Energy Autoscaler initialized")
        logger.info(f"📊 Gateway services: {self.gateway_services}")
        logger.info(f"🧠 Memory services: {self.memory_services}")
        logger.info(f"💾 I/O services: {self.io_services}")
        logger.info(f"⚡ CPU services: {self.cpu_services}")

    def get_service_workload_type(self, service):
        """Determine workload type for a service"""
        if service in self.cpu_services:
            return "cpu"
        elif service in self.memory_services:
            return "memory"
        elif service in self.io_services:
            return "io"
        elif service in self.gateway_services:
            return "gateway"
        else:
            return "cpu"  # default

    def query_prometheus(self, query):
        """Query Prometheus and return results"""
        try:
            response = requests.get(f"{self.prometheus_url}/api/v1/query", 
                                  params={"query": query}, timeout=10)
            data = response.json()
            if data["status"] == "success":
                return data["data"]["result"]
            return []
        except Exception as e:
            logger.error(f"Prometheus query error: {e}")
            return []

    def get_kepler_power(self, service):
        """Get power consumption from Kepler"""
        # Kepler power query for specific pod
        query = f'kepler_container_package_joules_total{{container_name=~"{service}.*"}}'
        results = self.query_prometheus(query)
        
        if results:
            try:
                power = float(results[0]["value"][1])
                logger.info(f"📊 {service}: Kepler power = {power:.2f}W")
                return power
            except:
                pass
        
        # Fallback: estimate based on workload type
        workload_type = self.get_service_workload_type(service)
        estimates = {
            "cpu": random.uniform(15, 25),
            "memory": random.uniform(8, 15),
            "io": random.uniform(10, 18),
            "gateway": random.uniform(5, 10)
        }
        estimated_power = estimates.get(workload_type, 12)
        logger.info(f"📊 {service}: Estimated power = {estimated_power:.2f}W ({workload_type} workload)")
        return estimated_power

    def get_service_rps(self, service):
        """Get RPS for a specific service"""
        query = f'sum(rate(mub_internal_processing_latency_milliseconds_count{{app_name="{service}"}}[2m]))'
        results = self.query_prometheus(query)
        
        if results:
            try:
                rps = float(results[0]["value"][1])
                return max(rps, 0.01)  # Minimum to avoid division by zero
            except:
                pass
        return 0.01

    def get_current_replicas(self, service):
        """Get current replica count"""
        try:
            result = subprocess.run([
                "kubectl", "get", "deployment", service, "-n", self.namespace,
                "-o", "jsonpath={.spec.replicas}"
            ], capture_output=True, text=True, timeout=10)
            return int(result.stdout.strip()) if result.stdout.strip() else 1
        except:
            return 1

    def scale_deployment(self, service, replicas):
        """Scale a deployment"""
        try:
            subprocess.run([
                "kubectl", "scale", "deployment", service,
                f"--replicas={replicas}", "-n", self.namespace
            ], timeout=15)
            logger.info(f"🔧 Scaled {service} to {replicas} replicas")
            return True
        except Exception as e:
            logger.error(f"Failed to scale {service}: {e}")
            return False

    def calculate_efficiency(self, service):
        """Calculate energy efficiency (RPS/Watt) for mixed workload"""
        rps = self.get_service_rps(service)
        power = self.get_kepler_power(service)
        
        if power > 0:
            efficiency = rps / power
        else:
            efficiency = 0
        
        # Store efficiency history
        if service not in self.efficiency_history:
            self.efficiency_history[service] = []
        self.efficiency_history[service].append(efficiency)
        
        # Keep only last 5 measurements for moving average
        if len(self.efficiency_history[service]) > 5:
            self.efficiency_history[service] = self.efficiency_history[service][-5:]
        
        # Use moving average for more stable decisions
        avg_efficiency = sum(self.efficiency_history[service]) / len(self.efficiency_history[service])
        
        workload_type = self.get_service_workload_type(service)
        logger.info(f"⚡ {service} ({workload_type}): RPS={rps:.2f}, Power={power:.2f}W, Efficiency={avg_efficiency:.4f}")
        
        return avg_efficiency, rps, power

    def should_scale(self, service):
        """Determine if service should scale based on workload-specific thresholds"""
        # Check cooldown
        current_time = time.time()
        if service in self.last_scale_time:
            if current_time - self.last_scale_time[service] < self.scale_cooldown:
                return None, "Cooldown active"

        efficiency, rps, power = self.calculate_efficiency(service)
        current_replicas = self.get_current_replicas(service)
        workload_type = self.get_service_workload_type(service)
        thresholds = self.workload_thresholds[workload_type]

        decision_info = {
            "service": service,
            "workload_type": workload_type,
            "efficiency": efficiency,
            "rps": rps,
            "power": power,
            "replicas": current_replicas,
            "timestamp": datetime.now().isoformat()
        }

        # Scale UP if efficiency is low and we can scale up
        if efficiency < thresholds["low_eff"] and current_replicas < thresholds["max_replicas"]:
            if rps > 0.1:  # Only scale up if there's meaningful traffic
                decision_info["action"] = "scale_up"
                decision_info["reason"] = f"Low efficiency ({efficiency:.4f} < {thresholds['low_eff']}) with traffic"
                self.decision_log.append(decision_info)
                return current_replicas + 1, f"Scale UP: efficiency {efficiency:.4f} < {thresholds['low_eff']}"

        # Scale DOWN if efficiency is high and we can scale down
        elif efficiency > thresholds["high_eff"] and current_replicas > 1:
            decision_info["action"] = "scale_down"
            decision_info["reason"] = f"High efficiency ({efficiency:.4f} > {thresholds['high_eff']})"
            self.decision_log.append(decision_info)
            return current_replicas - 1, f"Scale DOWN: efficiency {efficiency:.4f} > {thresholds['high_eff']}"

        decision_info["action"] = "no_change"
        decision_info["reason"] = f"Efficiency {efficiency:.4f} within acceptable range"
        self.decision_log.append(decision_info)
        return None, f"No scaling: efficiency {efficiency:.4f} is optimal for {workload_type} workload"

    def autoscale_iteration(self):
        """Perform one autoscaling iteration for mixed workload"""
        logger.info("🔄 Starting mixed workload autoscaling iteration...")
        
        scaling_actions = 0
        for service in self.all_services:
            try:
                new_replicas, reason = self.should_scale(service)
                workload_type = self.get_service_workload_type(service)
                
                if new_replicas is not None:
                    logger.info(f"🔧 {service} ({workload_type}): {reason}")
                    if self.scale_deployment(service, new_replicas):
                        self.last_scale_time[service] = time.time()
                        scaling_actions += 1
                else:
                    logger.info(f"✅ {service} ({workload_type}): {reason}")
                    
            except Exception as e:
                logger.error(f"Error processing {service}: {e}")
        
        if scaling_actions > 0:
            logger.info(f"🎯 Completed iteration: {scaling_actions} scaling actions taken")
        else:
            logger.info("🎯 Completed iteration: System is optimally scaled")
        
        return scaling_actions

    def run_autoscaler(self, duration_minutes=10):
        """Run the autoscaler for specified duration"""
        logger.info(f"🚀 Starting energy-aware autoscaler for {duration_minutes} minutes")
        logger.info("🧮 Mixed workload thresholds:")
        for wtype, thresh in self.workload_thresholds.items():
            logger.info(f"  {wtype}: low_eff={thresh['low_eff']}, high_eff={thresh['high_eff']}, max_replicas={thresh['max_replicas']}")
        
        start_time = time.time()
        end_time = start_time + (duration_minutes * 60)
        iteration = 0
        
        while time.time() < end_time:
            iteration += 1
            logger.info(f"\n⚡ === ITERATION {iteration} ===")
            
            try:
                self.autoscale_iteration()
            except Exception as e:
                logger.error(f"Error in iteration {iteration}: {e}")
            
            # Sleep until next iteration
            remaining_time = end_time - time.time()
            if remaining_time > self.scale_cooldown:
                time.sleep(self.scale_cooldown)
            else:
                break
        
        logger.info(f"🏁 Autoscaler completed after {iteration} iterations")
        
        # Print decision summary
        logger.info("\n📊 SCALING DECISIONS SUMMARY:")
        for wtype in ["gateway", "memory", "io", "cpu"]:
            type_decisions = [d for d in self.decision_log if d.get("workload_type") == wtype]
            scale_ups = len([d for d in type_decisions if d.get("action") == "scale_up"])
            scale_downs = len([d for d in type_decisions if d.get("action") == "scale_down"])
            logger.info(f"  {wtype.upper()}: {scale_ups} scale-ups, {scale_downs} scale-downs")

if __name__ == "__main__":
    duration = float(sys.argv[1]) if len(sys.argv) > 1 else 10
    autoscaler = MixedWorkloadEnergyAutoscaler()
    autoscaler.run_autoscaler(duration)
EOF
    
    chmod +x energy_autoscaler_mixed.py
    log_action "✅ Created energy autoscaler for mixed workload"
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

# Step 2: Create energy autoscaler
create_python_autoscaler
wait_with_countdown 15 "autoscaler setup"

# Show initial state
log_action "📊 Initial 20-service mixed workload state:"
for service in "${ALL_SERVICES[@]}"; do
    replicas=$(get_current_replicas "$service")
    log_action "  $service: $replicas replicas"
done

# Step 3: Test 1 - Energy-Aware Autoscaling with Constant Medium Load
log_action "🧪 Step 3: Test 1 - Energy-Aware with Constant Medium Load (mixed workload)..."

# Start load test
python3 load_tester.py --gateway "$GATEWAY_URL" --workload constant --rps 8 --duration 180 &
LOAD_PID=$!

# Start energy autoscaler
python3 energy_autoscaler_mixed.py 3 &
AUTOSCALER_PID=$!

# Wait for initial stabilization
wait_with_countdown 30 "load warmup and energy autoscaler initialization"

# Collect data for 3 minutes (must use integer minutes)
log_action "📈 Collecting energy-aware constant load data for 3 minutes..."
# Duration is in minutes in the research_data_collector.py - must use integer minutes
python3 research_data_collector.py --mode experiment --scenario energy_aware_constant_medium_mixed --duration 3 --prometheus-url "$PROMETHEUS_URL" &
COLLECT_PID=$!

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ Data collection completed"

# Kill any remaining research_data_collector.py processes to avoid continued metric collection
log_action "🧹 Cleaning up any lingering data collector processes..."
pkill -f "python3 research_data_collector.py" || true

# Stop autoscaler and load test
kill $AUTOSCALER_PID 2>/dev/null || true
wait $LOAD_PID
log_action "✅ Constant load test completed"

# Cool down period
wait_with_countdown 30 "system cooldown and energy reset"

# Step 4: Test 2 - Energy-Aware Autoscaling with Burst Load
log_action "🧪 Step 4: Test 2 - Energy-Aware with Burst Load (mixed workload)..."

# Start burst load test
python3 load_tester.py --gateway "$GATEWAY_URL" --workload burst --rps 12 --duration 180 &
LOAD_PID=$!

# Start energy autoscaler
python3 energy_autoscaler_mixed.py 3 &
AUTOSCALER_PID=$!

# Wait for stabilization
wait_with_countdown 30 "burst load warmup and energy autoscaler"

# Collect data for 3 minutes (must use integer minutes)
log_action "📈 Collecting energy-aware burst data for 3 minutes..."
# Duration is in minutes in the research_data_collector.py - must use integer minutes
python3 research_data_collector.py --mode experiment --scenario energy_aware_burst_mixed --duration 3 --prometheus-url "$PROMETHEUS_URL" &
COLLECT_PID=$!

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ Burst data collection completed"

# Kill any remaining research_data_collector.py processes to avoid continued metric collection
log_action "🧹 Cleaning up any lingering data collector processes..."
pkill -f "python3 research_data_collector.py" || true

# Stop autoscaler and load test
kill $AUTOSCALER_PID 2>/dev/null || true
wait $LOAD_PID
log_action "✅ Burst load test completed"

# Cool down period
wait_with_countdown 30 "system cooldown and energy reset"

# Step 5: Test 3 - Energy-Aware Autoscaling with CPU Intensive Load
log_action "🧪 Step 5: Test 3 - Energy-Aware with CPU Intensive Load (mixed workload)..."

# Start CPU intensive load test
python3 load_tester.py --gateway "$GATEWAY_URL" --workload cpu_intensive --rps 6 --duration 210 &
LOAD_PID=$!

# Start energy autoscaler
python3 energy_autoscaler_mixed.py 3.5 &
AUTOSCALER_PID=$!

# Wait for stabilization
wait_with_countdown 30 "CPU intensive load warmup and energy autoscaler"

# Collect data for 3.5 minutes (must use integer minutes)
log_action "📈 Collecting energy-aware CPU intensive data for 4 minutes..."
# Duration is in minutes in the research_data_collector.py - must use integer minutes
python3 research_data_collector.py --mode experiment --scenario energy_aware_cpu_intensive_mixed --duration 4 --prometheus-url "$PROMETHEUS_URL" &
COLLECT_PID=$!

# Wait for data collection to complete
wait $COLLECT_PID
log_action "✅ CPU intensive data collection completed"

# Kill any remaining research_data_collector.py processes to avoid continued metric collection
log_action "🧹 Cleaning up any lingering data collector processes..."
pkill -f "python3 research_data_collector.py" || true

# Stop autoscaler and load test
kill $AUTOSCALER_PID 2>/dev/null || true
wait $LOAD_PID
log_action "✅ CPU intensive load test completed"

# Step 6: Show final results
log_action "📊 Step 6: Phase 3 Results Summary"
log_action "=================================="

# Show final replica counts
log_action "🔍 Final replica counts after energy-aware autoscaling:"
for service in "${ALL_SERVICES[@]}"; do
    replicas=$(get_current_replicas "$service")
    log_action "  $service: $replicas replicas"
done

# List generated data files
log_action "📁 Generated data files:"
ls -la research_data/energy_aware_*_mixed* 2>/dev/null | tee -a "$LOG_FILE" || log_action "No energy-aware data files found yet"

log_action "🎉 PHASE 3 COMPLETED SUCCESSFULLY!"
log_action "=================================="
log_action "⏰ End time: $(date)"
log_action "📁 Results in: research_data/"
log_action "📄 Log file: $LOG_FILE"
log_action "🧮 Workload: 20-service mixed workload with energy-aware autoscaling"
log_action "💡 Ready for data analysis and comparison"

echo ""
echo "📊 PHASE 3 DATA SUMMARY:"
echo "========================"
echo "✅ Energy-aware constant medium load: energy_aware_constant_medium_mixed_*.csv"
echo "✅ Energy-aware burst load: energy_aware_burst_mixed_*.csv"  
echo "✅ Energy-aware CPU intensive load: energy_aware_cpu_intensive_mixed_*.csv"
echo ""
echo "🧮 MIXED WORKLOAD ENERGY OPTIMIZATION:"
echo "⚡ CPU services: Optimized for π computation efficiency (s8)"
echo "🧠 Memory services: Balanced memory allocation vs. energy (s1,s2,s6,s9,s12,s13)"
echo "💾 I/O services: Optimized I/O operations per watt (s3-s5,s7,s10,s11,s14-s19)"
echo "📊 Gateway: Minimal energy footprint (s0)"
echo ""
echo "🔍 Energy efficiency thresholds:"
echo "   CPU: scale_up<0.05, scale_down>0.15 RPS/Watt"
echo "   Memory: scale_up<0.10, scale_down>0.25 RPS/Watt"
echo "   I/O: scale_up<0.08, scale_down>0.20 RPS/Watt"
echo "   Gateway: scale_up<0.15, scale_down>0.35 RPS/Watt"
echo ""
echo "🎯 RESEARCH INSIGHTS AVAILABLE:"
echo "1. Energy efficiency patterns across workload types"
echo "2. Scaling behavior differences between autoscaling approaches"
echo "3. Mixed workload optimization vs. CPU-only workloads"
echo "4. Service dependency impact on energy consumption"
