#!/usr/bin/env python3
"""
Energy monitoring script for muBench microservices
Calculates EPR (Energy Per Request) and other key metrics
"""

import requests
import json
import time
from datetime import datetime, timedelta

class EnergyMonitor:
    def __init__(self, prometheus_url="http://localhost:9090"):
        self.prometheus_url = prometheus_url
        
    def query_prometheus(self, query):
        """Query Prometheus and return results"""
        try:
            response = requests.get(f"{self.prometheus_url}/api/v1/query", 
                                  params={'query': query})
            return response.json()
        except Exception as e:
            print(f"Error querying Prometheus: {e}")
            return None
    
    def get_epr_by_service(self):
        """Calculate Energy Per Request for each service"""
        # Energy rate (Watts)
        energy_query = 'rate(kepler_container_energy_stat{container_name!="POD"}[5m])'
        
        # Request rate (RPS)
        request_query = 'rate(mub_request_processing_latency_milliseconds_count[5m])'
        
        energy_data = self.query_prometheus(energy_query)
        request_data = self.query_prometheus(request_query)
        
        if not energy_data or not request_data:
            return {}
            
        # Process results
        epr_results = {}
        
        for energy_metric in energy_data['data']['result']:
            pod_name = energy_metric['metric'].get('pod', '')
            service_name = pod_name.split('-')[0] if pod_name else 'unknown'
            energy_rate = float(energy_metric['value'][1])
            
            # Find corresponding request rate
            for request_metric in request_data['data']['result']:
                if request_metric['metric'].get('kubernetes_service', '') == service_name:
                    request_rate = float(request_metric['value'][1])
                    if request_rate > 0:
                        epr = energy_rate / request_rate  # Joules per request
                        epr_results[service_name] = {
                            'epr_joules_per_request': epr,
                            'power_watts': energy_rate,
                            'request_rate_rps': request_rate,
                            'pod_name': pod_name
                        }
                    break
        
        return epr_results
    
    def get_service_metrics(self):
        """Get comprehensive metrics for all services"""
        metrics = {}
        
        # Replica counts
        replica_query = 'kube_deployment_status_replicas{deployment=~"s[0-9]+"}'
        replica_data = self.query_prometheus(replica_query)
        
        # Latency percentiles
        p95_query = 'histogram_quantile(0.95, rate(mub_request_processing_latency_milliseconds_bucket[5m]))'
        p99_query = 'histogram_quantile(0.99, rate(mub_request_processing_latency_milliseconds_bucket[5m]))'
        
        p95_data = self.query_prometheus(p95_query)
        p99_data = self.query_prometheus(p99_query)
        
        # Power consumption
        power_query = 'kepler_container_power_stat{container_name!="POD"}'
        power_data = self.query_prometheus(power_query)
        
        # Request rates
        rps_query = 'rate(mub_request_processing_latency_milliseconds_count{kubernetes_service=~"s[0-9]+"}[5m])'
        rps_data = self.query_prometheus(rps_query)
        
        # Process all metrics
        if replica_data:
            for metric in replica_data['data']['result']:
                service = metric['metric']['deployment']
                if service not in metrics:
                    metrics[service] = {}
                metrics[service]['replicas'] = int(metric['value'][1])
        
        if p95_data:
            for metric in p95_data['data']['result']:
                service = metric['metric'].get('kubernetes_service', '')
                if service and service in metrics:
                    metrics[service]['latency_p95_ms'] = float(metric['value'][1])
        
        if p99_data:
            for metric in p99_data['data']['result']:
                service = metric['metric'].get('kubernetes_service', '')
                if service and service in metrics:
                    metrics[service]['latency_p99_ms'] = float(metric['value'][1])
        
        if power_data:
            for metric in power_data['data']['result']:
                pod_name = metric['metric'].get('pod', '')
                service = pod_name.split('-')[0] if pod_name else ''
                if service and service in metrics:
                    metrics[service]['power_watts'] = float(metric['value'][1])
        
        if rps_data:
            for metric in rps_data['data']['result']:
                service = metric['metric'].get('kubernetes_service', '')
                if service and service in metrics:
                    metrics[service]['rps'] = float(metric['value'][1])
        
        return metrics
    
    def get_inefficient_services(self):
        """Identify services with high latency and high energy consumption"""
        # Services with P95 latency > 1000ms AND power consumption > 2W
        inefficient_query = '''
        (histogram_quantile(0.95, rate(mub_request_processing_latency_milliseconds_bucket[5m])) > 1000) 
        * on(kubernetes_service) group_left() 
        (kepler_container_power_stat{container_name!="POD"} > 2)
        '''
        
        result = self.query_prometheus(inefficient_query)
        
        if not result or 'data' not in result:
            return []
            
        inefficient_services = []
        for metric in result['data']['result']:
            service_name = metric['metric'].get('kubernetes_service', 'unknown')
            value = float(metric['value'][1])
            
            inefficient_services.append({
                'service': service_name,
                'inefficiency_score': value,
                'metric_labels': metric['metric']
            })
        
        return inefficient_services
    
    def get_energy_performance_analysis(self):
        """Comprehensive energy vs performance analysis"""
        analysis = {}
        
        # Get P95 latencies
        p95_query = 'histogram_quantile(0.95, rate(mub_request_processing_latency_milliseconds_bucket[5m])) by (kubernetes_service)'
        p95_data = self.query_prometheus(p95_query)
        
        # Get power consumption
        power_query = 'kepler_container_power_stat{container_name!="POD"} * on(pod) group_left(app) kube_pod_labels{label_app=~"s[0-9]+"}'
        power_data = self.query_prometheus(power_query)
        
        # Get request rates
        rps_query = 'rate(mub_request_processing_latency_milliseconds_count[5m]) by (kubernetes_service)'
        rps_data = self.query_prometheus(rps_query)
        
        # Combine metrics
        if p95_data:
            for metric in p95_data['data']['result']:
                service = metric['metric'].get('kubernetes_service', '')
                if service:
                    analysis[service] = {
                        'latency_p95_ms': float(metric['value'][1]),
                        'power_watts': 0,
                        'rps': 0,
                        'efficiency_score': 0
                    }
        
        if power_data:
            for metric in power_data['data']['result']:
                pod_name = metric['metric'].get('pod', '')
                service = pod_name.split('-')[0] if pod_name else ''
                if service in analysis:
                    analysis[service]['power_watts'] = float(metric['value'][1])
        
        if rps_data:
            for metric in rps_data['data']['result']:
                service = metric['metric'].get('kubernetes_service', '')
                if service in analysis:
                    analysis[service]['rps'] = float(metric['value'][1])
        
        # Calculate efficiency scores
        for service, metrics in analysis.items():
            if metrics['power_watts'] > 0:
                # Efficiency = RPS per Watt (higher is better)
                metrics['efficiency_score'] = metrics['rps'] / metrics['power_watts']
                
                # Flag inefficient services
                metrics['is_inefficient'] = (
                    metrics['latency_p95_ms'] > 1000 and 
                    metrics['power_watts'] > 2
                )
        
        return analysis
    
    def print_summary(self):
        """Print a comprehensive summary of all metrics"""
        print(f"\n{'='*80}")
        print(f"ENERGY-AWARE AUTOSCALING METRICS SUMMARY")
        print(f"Timestamp: {datetime.now()}")
        print(f"{'='*80}")
        
        # EPR Analysis
        epr_data = self.get_epr_by_service()
        if epr_data:
            print(f"\n📊 ENERGY PER REQUEST (EPR) ANALYSIS:")
            print(f"{'Service':<10} {'EPR (J/req)':<12} {'Power (W)':<10} {'RPS':<8} {'Pod':<20}")
            print("-" * 65)
            for service, data in epr_data.items():
                print(f"{service:<10} {data['epr_joules_per_request']:<12.6f} "
                      f"{data['power_watts']:<10.2f} {data['request_rate_rps']:<8.2f} "
                      f"{data['pod_name']:<20}")
        
        # Comprehensive metrics
        service_metrics = self.get_service_metrics()
        if service_metrics:
            print(f"\n📈 COMPREHENSIVE SERVICE METRICS:")
            print(f"{'Service':<8} {'Replicas':<8} {'RPS':<8} {'P95(ms)':<8} {'P99(ms)':<8} {'Power(W)':<8}")
            print("-" * 60)
            for service, metrics in service_metrics.items():
                replicas = metrics.get('replicas', 'N/A')
                rps = metrics.get('rps', 0)
                p95 = metrics.get('latency_p95_ms', 'N/A')
                p99 = metrics.get('latency_p99_ms', 'N/A')
                power = metrics.get('power_watts', 'N/A')
                
                print(f"{service:<8} {replicas:<8} {rps:<8.2f} "
                      f"{p95 if isinstance(p95, str) else f'{p95:.1f}':<8} "
                      f"{p99 if isinstance(p99, str) else f'{p99:.1f}':<8} "
                      f"{power if isinstance(power, str) else f'{power:.2f}':<8}")
        
        # Energy vs Performance Analysis
        energy_analysis = self.get_energy_performance_analysis()
        if energy_analysis:
            print(f"\n⚡ ENERGY vs PERFORMANCE ANALYSIS:")
            print(f"{'Service':<8} {'P95(ms)':<8} {'Power(W)':<9} {'RPS':<8} {'Eff(RPS/W)':<11} {'Status':<12}")
            print("-" * 70)
            for service, metrics in energy_analysis.items():
                status = "⚠️ INEFFICIENT" if metrics.get('is_inefficient', False) else "✅ OK"
                efficiency = metrics.get('efficiency_score', 0)
                
                print(f"{service:<8} {metrics['latency_p95_ms']:<8.1f} "
                      f"{metrics['power_watts']:<9.2f} {metrics['rps']:<8.2f} "
                      f"{efficiency:<11.3f} {status:<12}")
        
        # Inefficient services alert
        inefficient = self.get_inefficient_services()
        if inefficient:
            print(f"\n🚨 INEFFICIENT SERVICES ALERT:")
            print("Services with high latency (>1000ms) AND high power consumption (>2W):")
            for service_data in inefficient:
                print(f"   • {service_data['service']} (score: {service_data['inefficiency_score']:.2f})")
        else:
            print(f"\n✅ No highly inefficient services detected.")
        
        # Inefficient services
        inefficient_services = self.get_inefficient_services()
        if inefficient_services:
            print(f"\n🚨 INEFFICIENT SERVICES (High Latency & Energy):")
            print(f"{'Service':<10} {'Score':<10} {'Details'}")
            print("-" * 50)
            for service in inefficient_services:
                print(f"{service['service']:<10} {service['inefficiency_score']:<10.2f} "
                      f"{json.dumps(service['metric_labels'], indent=2)}")
        
        # Energy-performance analysis
        energy_perf_analysis = self.get_energy_performance_analysis()
        if energy_perf_analysis:
            print(f"\n⚡ ENERGY-PERFORMANCE ANALYSIS:")
            print(f"{'Service':<10} {'P95(ms)':<8} {'Power(W)':<8} {'RPS':<8} {'Efficiency':<12} {'Inefficient'}")
            print("-" * 70)
            for service, metrics in energy_perf_analysis.items():
                p95 = metrics.get('latency_p95_ms', 'N/A')
                power = metrics.get('power_watts', 'N/A')
                rps = metrics.get('rps', 0)
                efficiency = metrics.get('efficiency_score', 0)
                is_inefficient = "Yes" if metrics.get('is_inefficient', False) else "No"
                
                print(f"{service:<10} {p95 if isinstance(p95, str) else f'{p95:.1f}':<8} "
                      f"{power if isinstance(power, str) else f'{power:.2f}':<8} "
                      f"{rps:<8.2f} {efficiency:<12.4f} {is_inefficient:<12}")

def main():
    """Main monitoring function"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Energy monitoring for muBench')
    parser.add_argument('--prometheus-url', default='http://localhost:9090',
                       help='Prometheus URL (default: http://localhost:9090)')
    args = parser.parse_args()
    
    monitor = EnergyMonitor(prometheus_url=args.prometheus_url)
    
    print("🔋 Starting Energy-Aware Monitoring for muBench...")
    print(f"🔗 Connecting to Prometheus at: {args.prometheus_url}")
    print("💡 Make sure Prometheus is accessible (use minikube service or port-forward)")
    
    try:
        while True:
            monitor.print_summary()
            print(f"\n⏰ Next update in 30 seconds... (Ctrl+C to stop)")
            time.sleep(30)
    except KeyboardInterrupt:
        print(f"\n👋 Monitoring stopped.")

if __name__ == "__main__":
    main()
