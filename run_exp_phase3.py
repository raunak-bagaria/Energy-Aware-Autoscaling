import requests
import subprocess
import time
from datetime import datetime

# Configurations
PROMETHEUS_URL = "http://192.168.49.2:30000"  # Updated to match bash script
SERVICES = ["s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9"]
LOW_EFFICIENCY_THRESHOLD = 0.25   # Scale UP when efficiency < 0.25 (was 0.1)
HIGH_EFFICIENCY_THRESHOLD = 0.35  # Scale DOWN when efficiency > 0.35 (was 0.2)
MIN_REPLICAS = 1
MAX_REPLICAS = 5
NAMESPACE = "default"
SLEEP_INTERVAL = 60  # in seconds
RPS_SCALE_DOWN_THRESHOLD = 2.0    # Scale DOWN when RPS < 2.0 (was 0.5)

# Prometheus Query Templates
REPLICA_QUERY = 'kube_deployment_status_replicas{deployment=~"s[0-9]+"}'
POWER_QUERY = 'rate(kepler_container_joules_total{container_namespace="default"}[5m])'
RPS_QUERY = 'rate(mub_request_processing_latency_milliseconds_count{kubernetes_service=~"s[0-9]+"}[5m])'
LATENCY_P95_QUERY = 'histogram_quantile(0.95, rate(mub_request_processing_latency_milliseconds_bucket{kubernetes_service=~"s[0-9]+"}[5m]))'
LATENCY_P99_QUERY = 'histogram_quantile(0.99, rate(mub_request_processing_latency_milliseconds_bucket{kubernetes_service=~"s[0-9]+"}[5m]))'
ENERGY_TOTAL_QUERY = 'kepler_container_joules_total{container_namespace="default"}'

# Query Prometheus API
def query_prometheus(query):
    try:
        response = requests.get(f"{PROMETHEUS_URL}/api/v1/query", params={'query': query})
        response.raise_for_status()
        return response.json()['data']['result']
    except Exception as e:
        print(f"Error querying Prometheus: {e}")
        return None

# Get Current Replicas
def get_current_replicas(service):
    command = ["kubectl", "get", "deployment", service, "-n", NAMESPACE, "-o", "jsonpath={.spec.replicas}"]
    try:
        output = subprocess.check_output(command).decode().strip()
        return int(output)
    except Exception as e:
        print(f"[ERROR] Failed to get replicas for {service}: {e}")
        return None

# Scale Deployment
def scale_deployment(service, replicas):
    command = [
        "kubectl", "scale", "deployment", service,
        f"--replicas={replicas}", "-n", NAMESPACE
    ]
    try:
        subprocess.run(command, check=True)
        print(f"[INFO] Scaled {service} to {replicas} replicas.")
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] Scaling failed for {service}: {e}")

# Compute Metrics from Simplified Simulation (matching bash script approach)
def compute_metrics():
    metrics = {}
    
    for service in SERVICES:
        try:
            # Get current replicas from kubectl
            current_replicas = get_current_replicas(service)
            if current_replicas is None:
                current_replicas = 1
            
            # Simulate metrics (matching bash script logic)
            import random
            
            # Default values
            power = 1.5  # Default power consumption per service
            rps = 0      # Default RPS
            
            # Check if service has active pods
            command = ["kubectl", "get", "pods", "-l", f"app={service}", 
                      "--field-selector=status.phase=Running", "--no-headers"]
            try:
                output = subprocess.check_output(command, stderr=subprocess.DEVNULL).decode().strip()
                active_pods = len(output.split('\n')) if output else 0
            except:
                active_pods = 0
            
            # Estimate RPS based on active pods and replica count
            if active_pods > 0 and current_replicas > 0:
                # Simulate RPS activity
                base_rps = current_replicas * 1.5
                rps = max(0, base_rps + random.uniform(-0.5, 1.0))
                
                # Adjust power based on load
                base_power = 1.5
                power = base_power + (rps * 0.3)  # Power increases with RPS
            
            # Calculate efficiency (RPS per Watt)
            efficiency = rps / power if power > 0 else 0.0
            
            # Calculate EPR (Energy Per Request)
            epr = power / rps if rps > 0 else 0.0
            
            # Store metrics
            metrics[service] = {
                'replicas': current_replicas,
                'power_watts': power,
                'rps': rps,
                'efficiency_rps_per_watt': efficiency,
                'epr_joules_per_request': epr,
                'latency_p95_ms': 100 + random.uniform(0, 50),  # Simulated latency
                'latency_p99_ms': 150 + random.uniform(0, 100), # Simulated latency
                'total_energy_joules': power * 60  # Simulated total energy
            }
            
        except Exception as e:
            print(f"[ERROR] Failed to compute metrics for {service}: {e}")
            # Fallback metrics
            metrics[service] = {
                'replicas': 1,
                'power_watts': 1.5,
                'rps': 0,
                'efficiency_rps_per_watt': 0,
                'epr_joules_per_request': 0,
                'latency_p95_ms': 100,
                'latency_p99_ms': 150,
                'total_energy_joules': 90
            }
    
    return metrics

# Autoscale Based on Efficiency
def autoscale():
    metrics = compute_metrics()

    for service, m in metrics.items():
        eff = m.get('efficiency_rps_per_watt', 0)
        rps = m.get('rps', 0)
        current_replicas = m.get('replicas', 1)

        if eff < LOW_EFFICIENCY_THRESHOLD and current_replicas < MAX_REPLICAS:
            new_replicas = current_replicas + 1
            scale_deployment(service, new_replicas)
            print(f"[SCALE UP] {service}: efficiency={eff:.3f} < {LOW_EFFICIENCY_THRESHOLD}, rps={rps:.2f} -> {new_replicas} replicas")

        elif eff > HIGH_EFFICIENCY_THRESHOLD and rps < RPS_SCALE_DOWN_THRESHOLD and current_replicas > MIN_REPLICAS:
            new_replicas = current_replicas - 1
            scale_deployment(service, new_replicas)
            print(f"[SCALE DOWN] {service}: efficiency={eff:.3f} > {HIGH_EFFICIENCY_THRESHOLD}, rps={rps:.2f} < {RPS_SCALE_DOWN_THRESHOLD} -> {new_replicas} replicas")

        else:
            print(f"[NO SCALE] {service}: efficiency={eff:.3f}, rps={rps:.2f}, replicas={current_replicas}")

# Main loop
if __name__ == "__main__":
    while True:
        print(f"[INFO] Running autoscaler iteration...")
        autoscale()
        time.sleep(SLEEP_INTERVAL)