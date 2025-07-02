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
       
        # Working queries based on your confirmed Prometheus queries
        replica_query = 'kube_deployment_status_replicas{deployment=~"s[0-9]+"}'                                                
        power_query = 'rate(kepler_container_joules_total{container_namespace="default"}[5m])'
        
        # Updated to use working muBench queries with app_name
        rps_query = 'sum by (app_name) (rate(mub_internal_processing_latency_milliseconds_count{}[2m]))'
        service_delay_query = '''sum by (app_name) (increase(mub_request_processing_latency_milliseconds_sum{}[2m])) / 
                                sum by (app_name) (increase(mub_request_processing_latency_milliseconds_count{}[2m]))'''
        internal_delay_query = '''sum by (app_name) (increase(mub_internal_processing_latency_milliseconds_sum{}[2m])) / 
                                 sum by (app_name) (increase(mub_internal_processing_latency_milliseconds_count{}[2m]))'''
        external_delay_query = '''sum by (app_name) (increase(mub_external_processing_latency_milliseconds_sum{}[2m])) / 
                                 sum by (app_name) (increase(mub_external_processing_latency_milliseconds_count{}[2m]))'''
        
        energy_total_query = 'kepler_container_joules_total{container_namespace="default"}'
       
        # Execute all queries
        replica_data = self.query_prometheus(replica_query)
        power_data = self.query_prometheus(power_query)
        rps_data = self.query_prometheus(rps_query)
        service_delay_data = self.query_prometheus(service_delay_query)
        internal_delay_data = self.query_prometheus(internal_delay_query)
        external_delay_data = self.query_prometheus(external_delay_query)
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

        # Process RPS data using working query
        if rps_data and rps_data.get('data', {}).get('result'):
            for metric in rps_data['data']['result']:
                app_name = metric['metric'].get('app_name', '')
                if app_name:
                    if app_name not in metrics:
                        metrics[app_name] = {}
                    rps_value = float(metric['value'][1])
                    metrics[app_name]['rps'] = rps_value
                    print(f"✅ RPS data for {app_name}: {rps_value:.3f}")

        # Process service delay (total latency) data
        if service_delay_data and service_delay_data.get('data', {}).get('result'):
            for metric in service_delay_data['data']['result']:
                app_name = metric['metric'].get('app_name', '')
                if app_name:
                    if app_name not in metrics:
                        metrics[app_name] = {}
                    delay_ms = float(metric['value'][1])
                    metrics[app_name]['service_delay_ms'] = delay_ms
                    print(f"✅ Service delay for {app_name}: {delay_ms:.3f}ms")

        # Process internal delay data
        if internal_delay_data and internal_delay_data.get('data', {}).get('result'):
            for metric in internal_delay_data['data']['result']:
                app_name = metric['metric'].get('app_name', '')
                if app_name:
                    if app_name not in metrics:
                        metrics[app_name] = {}
                    internal_delay = float(metric['value'][1])
                    metrics[app_name]['internal_delay_ms'] = internal_delay
                    print(f"✅ Internal delay for {app_name}: {internal_delay:.3f}ms")

        # Process external delay data
        if external_delay_data and external_delay_data.get('data', {}).get('result'):
            for metric in external_delay_data['data']['result']:
                app_name = metric['metric'].get('app_name', '')
                if app_name:
                    if app_name not in metrics:
                        metrics[app_name] = {}
                    external_delay = float(metric['value'][1])
                    metrics[app_name]['external_delay_ms'] = external_delay
                    print(f"✅ External delay for {app_name}: {external_delay:.3f}ms")

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
            
            # Calculate latency-based efficiency metrics
            service_delay = m.get('service_delay_ms', 0)
            if service_delay > 0 and rps > 0:
                # Throughput efficiency: RPS per ms of latency
                m['throughput_efficiency'] = rps / service_delay
            else:
                m['throughput_efficiency'] = 0

        return metrics

    def print_summary(self):
        print(f"\n{'='*90}")
        print(f"ENERGY-AWARE AUTOSCALING METRICS SUMMARY")
        print(f"Timestamp: {datetime.now()}")
        print(f"{'='*90}")

        metrics = self.get_service_metrics()
        if metrics:
            print(f"\n📈 COMPREHENSIVE SERVICE METRICS:")
            print(f"{'Service':<8} {'Rep':<4} {'RPS':<8} {'Power(W)':<9} {'SvcLat(ms)':<11} {'IntLat(ms)':<11} {'ExtLat(ms)':<11} {'EPR(mJ)':<9} {'Eff(R/W)':<9}")
            print("-" * 90)
            
            for service, m in metrics.items():
                replicas = m.get('replicas', 'N/A')
                rps = m.get('rps', 0)
                power = m.get('power_watts', 0)
                service_lat = m.get('service_delay_ms', 0)
                internal_lat = m.get('internal_delay_ms', 0)  
                external_lat = m.get('external_delay_ms', 0)
                epr_mj = m.get('epr_joules_per_request', 0) * 1000  # Convert to millijoules
                efficiency = m.get('efficiency_rps_per_watt', 0)
                
                print(f"{service:<8} {replicas:<4} {rps:<8.3f} {power:<9.3f} {service_lat:<11.1f} "
                      f"{internal_lat:<11.1f} {external_lat:<11.1f} {epr_mj:<9.3f} {efficiency:<9.3f}")
            
            # Print insights
            print(f"\n🔍 ENERGY & LATENCY INSIGHTS:")
            
            # Energy insights
            high_epr_services = [svc for svc, m in metrics.items() if m.get('epr_joules_per_request', 0) > 0.005]
            inefficient_services = [svc for svc, m in metrics.items() if m.get('efficiency_rps_per_watt', 0) < 0.1 and m.get('rps', 0) > 0]
            
            # Latency insights
            high_service_latency = [svc for svc, m in metrics.items() if m.get('service_delay_ms', 0) > 100]
            high_internal_latency = [svc for svc, m in metrics.items() if m.get('internal_delay_ms', 0) > 50]
            high_external_latency = [svc for svc, m in metrics.items() if m.get('external_delay_ms', 0) > 50]
            
            if high_epr_services:
                print(f"⚡ High EPR services (>5mJ/req): {', '.join(high_epr_services)}")
            if inefficient_services:
                print(f"📉 Energy inefficient services (<0.1 RPS/W): {', '.join(inefficient_services)}")
            if high_service_latency:
                print(f"🐌 High service latency (>100ms): {', '.join(high_service_latency)}")
            if high_internal_latency:
                print(f"🔧 High internal latency (>50ms): {', '.join(high_internal_latency)}")
            if high_external_latency:
                print(f"🌐 High external latency (>50ms): {', '.join(high_external_latency)}")
                
            # System totals
            total_rps = sum(m.get('rps', 0) for m in metrics.values())
            total_power = sum(m.get('power_watts', 0) for m in metrics.values())
            total_replicas = sum(m.get('replicas', 0) for m in metrics.values() if isinstance(m.get('replicas'), int))
            
            print(f"\n🎯 SYSTEM TOTALS:")
            print(f"   Total RPS: {total_rps:.3f}")
            print(f"   Total Power: {total_power:.3f}W")
            print(f"   Total Replicas: {total_replicas}")
            if total_power > 0:
                print(f"   Overall Efficiency: {total_rps/total_power:.6f} RPS/W")
                
        else:
            print("❌ No metrics available - check Prometheus connection and muBench deployment")

    def run(self):
        print("🔋 Starting Energy-Aware Monitoring for muBench...")
        print(f"🔗 Connecting to Prometheus at: {self.prometheus_url}")
        print("📊 Using working muBench queries for latency metrics")
       
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