#!/usr/bin/env python3
"""
Energy monitoring script for muBench microservices
Calculates EPR (Energy Per Request) and other key metrics
"""

import requests
import json
import time
from datetime import datetime
import re

class EnergyMonitor:
    def __init__(self, prometheus_url="http://192.168.49.2:30000"):
        self.prometheus_url = prometheus_url

    def query_prometheus(self, query):
        try:
            response = requests.get(f"{self.prometheus_url}/api/v1/query",
                                    params={'query': query})
            result = response.json()
            if result.get('status') == 'success':
                return result
            else:
                print(f"Prometheus query failed: {result}")
                return None
        except Exception as e:
            print(f"Error querying Prometheus: {e}")
            return None

    def extract_service_name(self, pod_name):
        # Extract service name from pod name (e.g., s6-75bfb5dffb-q5trn -> s6)
        match = re.match(r'(s[0-9]+)', pod_name)
        return match.group(1) if match else None

    def get_service_metrics(self):
        metrics = {}
       
        # Enhanced queries for comprehensive metrics
        replica_query = 'kube_deployment_status_replicas{deployment=~"s[0-9]+"}'                                                
        power_query = 'rate(kepler_container_joules_total{container_namespace="default"}[5m])'
        rps_query = 'rate(mub_request_processing_latency_milliseconds_count{kubernetes_service=~"s[0-9]+"}[5m])'
        latency_p95_query = 'histogram_quantile(0.95, rate(mub_request_processing_latency_milliseconds_bucket{kubernetes_service=~"s[0-9]+"}[5m]))'
        latency_p99_query = 'histogram_quantile(0.99, rate(mub_request_processing_latency_milliseconds_bucket{kubernetes_service=~"s[0-9]+"}[5m]))'
        energy_total_query = 'kepler_container_joules_total{container_namespace="default"}'
       
        replica_data = self.query_prometheus(replica_query)
        power_data = self.query_prometheus(power_query)
        rps_data = self.query_prometheus(rps_query)
        latency_p95_data = self.query_prometheus(latency_p95_query)
        latency_p99_data = self.query_prometheus(latency_p99_query)
        energy_total_data = self.query_prometheus(energy_total_query)

        # Process replica data
        if replica_data and replica_data.get('data', {}).get('result'):
            for metric in replica_data['data']['result']:
                service = metric['metric']['deployment']
                if service not in metrics:
                    metrics[service] = {}
                metrics[service]['replicas'] = int(metric['value'][1])

        # Process power data with aggregation per service
        if power_data and power_data.get('data', {}).get('result'):
            service_power = {}
            for metric in power_data['data']['result']:
                pod_name = metric['metric'].get('pod_name', '')
                mode = metric['metric'].get('mode', '')
               
                service = self.extract_service_name(pod_name)
                if service:
                    power_value = float(metric['value'][1])
                    # Only include dynamic mode values (exclude idle mode which is usually 0)
                    if mode == 'dynamic' and power_value > 0:
                        if service not in service_power:
                            service_power[service] = []
                        service_power[service].append(power_value)
           
            # Aggregate power per service (sum all containers/pods)
            for service, power_values in service_power.items():
                if service not in metrics:
                    metrics[service] = {}
                metrics[service]['power_watts'] = sum(power_values)

        # Process RPS data
        if rps_data and rps_data.get('data', {}).get('result'):
            for metric in rps_data['data']['result']:
                service = metric['metric'].get('kubernetes_service', '')
                if service:
                    if service not in metrics:
                        metrics[service] = {}
                    rps_value = float(metric['value'][1])
                    metrics[service]['rps'] = rps_value

        # Process latency P95 data
        if latency_p95_data and latency_p95_data.get('data', {}).get('result'):
            for metric in latency_p95_data['data']['result']:
                service = metric['metric'].get('kubernetes_service', '')
                if service:
                    if service not in metrics:
                        metrics[service] = {}
                    latency_p95 = float(metric['value'][1])
                    metrics[service]['latency_p95_ms'] = latency_p95

        # Process latency P99 data
        if latency_p99_data and latency_p99_data.get('data', {}).get('result'):
            for metric in latency_p99_data['data']['result']:
                service = metric['metric'].get('kubernetes_service', '')
                if service:
                    if service not in metrics:
                        metrics[service] = {}
                    latency_p99 = float(metric['value'][1])
                    metrics[service]['latency_p99_ms'] = latency_p99

        # Process total energy data for EPR calculation
        if energy_total_data and energy_total_data.get('data', {}).get('result'):
            service_energy = {}
            for metric in energy_total_data['data']['result']:
                pod_name = metric['metric'].get('pod_name', '')
                service = self.extract_service_name(pod_name)
                if service:
                    energy_value = float(metric['value'][1])
                    if service not in service_energy:
                        service_energy[service] = []
                    service_energy[service].append(energy_value)
            
            # Store total energy per service
            for service, energy_values in service_energy.items():
                if service not in metrics:
                    metrics[service] = {}
                metrics[service]['total_energy_joules'] = sum(energy_values)

        # Calculate EPR (Energy Per Request) and efficiency
        for service, m in metrics.items():
            rps = m.get('rps', 0)
            power = m.get('power_watts', 0)
            total_energy = m.get('total_energy_joules', 0)
            
            # Calculate EPR: if we have RPS and power consumption
            if rps > 0 and power > 0:
                # EPR = Power (Watts) / RPS = Joules per request
                m['epr_joules_per_request'] = power / rps
            else:
                m['epr_joules_per_request'] = 0
            
            # Calculate efficiency (RPS per Watt)
            if power > 0:
                m['efficiency_rps_per_watt'] = rps / power
            else:
                m['efficiency_rps_per_watt'] = 0

        return metrics

    def print_summary(self):
        print(f"\n{'='*80}")
        print(f"ENERGY-AWARE AUTOSCALING METRICS SUMMARY")
        print(f"Timestamp: {datetime.now()}")
        print(f"{'='*80}")

        metrics = self.get_service_metrics()
        if metrics:
            print(f"\n📈 COMPREHENSIVE SERVICE METRICS:")
            print(f"{'Service':<8} {'Replicas':<8} {'RPS':<8} {'Power(W)':<9} {'EPR(mJ)':<9} {'Eff(R/W)':<9}")
            print("-" * 60)
            for service, m in metrics.items():
                epr_mj = m.get('epr_joules_per_request', 0) * 1000  # Convert to millijoules
                print(f"{service:<8} {m.get('replicas', 'N/A'):<8} {m.get('rps', 0):<8.2f} {m.get('power_watts', 0):<9.2f} "
                      f"{epr_mj:<9.3f} {m.get('efficiency_rps_per_watt', 0):<9.3f}")
            
            # Print insights
            print(f"\n🔍 ENERGY INSIGHTS:")
            high_epr_services = [svc for svc, m in metrics.items() if m.get('epr_joules_per_request', 0) > 0.001]
            high_latency_services = [svc for svc, m in metrics.items() if m.get('latency_p99_ms', 0) > 1000]
            inefficient_services = [svc for svc, m in metrics.items() if m.get('efficiency_rps_per_watt', 0) < 1.0 and m.get('rps', 0) > 0]
            
            if high_epr_services:
                print(f"⚡ High EPR services (>1mJ/req): {', '.join(high_epr_services)}")
            if high_latency_services:
                print(f"🐌 High latency services (P99>1s): {', '.join(high_latency_services)}")
            if inefficient_services:
                print(f"📉 Inefficient services (<1 RPS/W): {', '.join(inefficient_services)}")
        else:
            print("❌ No metrics available.")

    def run(self):
        print("🔋 Starting Energy-Aware Monitoring for muBench...")
        print(f"🔗 Connecting to Prometheus at: {self.prometheus_url}")
       
        try:
            while True:
                self.print_summary()
                print(f"\n⏰ Next update in 30 seconds... (Ctrl+C to stop)")
                time.sleep(30)
        except KeyboardInterrupt:
            print(f"\n👋 Monitoring stopped.")

def main():
    monitor = EnergyMonitor()
    monitor.run()

if __name__ == "__main__":
    main()
