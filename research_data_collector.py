#!/usr/bin/env python3
"""
Comprehensive data collection script for energy-aware autoscaling research
Collects baseline and experimental data for comparison
"""

import json
import time
import csv
import os
from datetime import datetime
from energy_monitoring import EnergyMonitor
import subprocess
import argparse

class ResearchDataCollector:
    def __init__(self, prometheus_url="http://192.168.49.2:30000", output_dir="research_data"):
        self.energy_monitor = EnergyMonitor(prometheus_url)
        self.output_dir = output_dir
        self.create_output_directory()
        
    def create_output_directory(self):
        """Create output directory for research data"""
        if not os.path.exists(self.output_dir):
            os.makedirs(self.output_dir)
            
    def collect_baseline_metrics(self, duration_minutes=10, interval_seconds=30):
        """Collect baseline metrics without any load"""
        print(f"🔬 Collecting baseline metrics for {duration_minutes} minutes...")
        
        baseline_data = []
        start_time = datetime.now()
        end_time = start_time.timestamp() + (duration_minutes * 60)
        
        while time.time() < end_time:
            timestamp = datetime.now()
            metrics = self.energy_monitor.get_service_metrics()
            
            for service, m in metrics.items():
                baseline_data.append({
                    'timestamp': timestamp.isoformat(),
                    'service': service,
                    'scenario': 'baseline',
                    'replicas': m.get('replicas', 0),
                    'rps': m.get('rps', 0),
                    'power_watts': m.get('power_watts', 0),
                    'epr_joules_per_request': m.get('epr_joules_per_request', 0),
                    'latency_p95_ms': m.get('latency_p95_ms', 0),
                    'latency_p99_ms': m.get('latency_p99_ms', 0),
                    'efficiency_rps_per_watt': m.get('efficiency_rps_per_watt', 0),
                    'total_energy_joules': m.get('total_energy_joules', 0)
                })
            
            print(f"📊 Collected baseline data point at {timestamp.strftime('%H:%M:%S')}")
            time.sleep(interval_seconds)
        
        # Save baseline data
        filename = f"{self.output_dir}/baseline_metrics_{start_time.strftime('%Y%m%d_%H%M%S')}.csv"
        self.save_to_csv(baseline_data, filename)
        print(f"💾 Baseline data saved to {filename}")
        
        return baseline_data
    
    def collect_experiment_metrics(self, scenario_name, duration_minutes=20, interval_seconds=30):
        """Collect metrics during an experiment scenario"""
        print(f"🧪 Collecting {scenario_name} experiment metrics for {duration_minutes} minutes...")
        
        experiment_data = []
        start_time = datetime.now()
        end_time = start_time.timestamp() + (duration_minutes * 60)
        
        while time.time() < end_time:
            timestamp = datetime.now()
            metrics = self.energy_monitor.get_service_metrics()
            
            # Also collect HPA status
            hpa_status = self.get_hpa_status()
            
            for service, m in metrics.items():
                experiment_data.append({
                    'timestamp': timestamp.isoformat(),
                    'service': service,
                    'scenario': scenario_name,
                    'replicas': m.get('replicas', 0),
                    'rps': m.get('rps', 0),
                    'power_watts': m.get('power_watts', 0),
                    'epr_joules_per_request': m.get('epr_joules_per_request', 0),
                    'latency_p95_ms': m.get('latency_p95_ms', 0),
                    'latency_p99_ms': m.get('latency_p99_ms', 0),
                    'efficiency_rps_per_watt': m.get('efficiency_rps_per_watt', 0),
                    'total_energy_joules': m.get('total_energy_joules', 0),
                    'hpa_enabled': service in hpa_status,
                    'hpa_target_replicas': hpa_status.get(service, {}).get('target_replicas', 0),
                    'hpa_current_replicas': hpa_status.get(service, {}).get('current_replicas', 0)
                })
            
            print(f"📊 Collected {scenario_name} data point at {timestamp.strftime('%H:%M:%S')}")
            time.sleep(interval_seconds)
        
        # Save experiment data
        filename = f"{self.output_dir}/{scenario_name}_metrics_{start_time.strftime('%Y%m%d_%H%M%S')}.csv"
        self.save_to_csv(experiment_data, filename)
        print(f"💾 {scenario_name} data saved to {filename}")
        
        return experiment_data
    
    def get_hpa_status(self):
        """Get HPA status for all services"""
        try:
            result = subprocess.run(['kubectl', 'get', 'hpa', '-o', 'json'], 
                                  capture_output=True, text=True)
            if result.returncode == 0:
                hpa_data = json.loads(result.stdout)
                hpa_status = {}
                
                for item in hpa_data.get('items', []):
                    service = item.get('spec', {}).get('scaleTargetRef', {}).get('name', '')
                    if service:
                        hpa_status[service] = {
                            'target_replicas': item.get('status', {}).get('desiredReplicas', 0),
                            'current_replicas': item.get('status', {}).get('currentReplicas', 0),
                            'current_cpu_utilization': item.get('status', {}).get('currentCPUUtilizationPercentage', 0)
                        }
                return hpa_status
        except Exception as e:
            print(f"Warning: Could not get HPA status: {e}")
            
        return {}
    
    def save_to_csv(self, data, filename):
        """Save data to CSV file"""
        if not data:
            return
            
        fieldnames = data[0].keys()
        
        with open(filename, 'w', newline='') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(data)
    
    def generate_summary_report(self, data_files):
        """Generate a summary report comparing different scenarios"""
        print(f"📋 Generating summary report...")
        
        summary = {
            'experiment_date': datetime.now().isoformat(),
            'scenarios': {},
            'key_findings': []
        }
        
        for file_path in data_files:
            scenario_name = os.path.basename(file_path).split('_')[0]
            
            # Load and analyze data
            with open(file_path, 'r') as f:
                import csv
                reader = csv.DictReader(f)
                scenario_data = list(reader)
            
            if scenario_data:
                # Calculate averages
                services = set(row['service'] for row in scenario_data)
                scenario_summary = {}
                
                for service in services:
                    service_data = [row for row in scenario_data if row['service'] == service]
                    if service_data:
                        avg_epr = sum(float(row['epr_joules_per_request']) for row in service_data) / len(service_data)
                        avg_power = sum(float(row['power_watts']) for row in service_data) / len(service_data)
                        avg_rps = sum(float(row['rps']) for row in service_data) / len(service_data)
                        avg_p99 = sum(float(row['latency_p99_ms']) for row in service_data) / len(service_data)
                        
                        scenario_summary[service] = {
                            'avg_epr_mj': avg_epr * 1000,
                            'avg_power_watts': avg_power,
                            'avg_rps': avg_rps,
                            'avg_p99_latency_ms': avg_p99,
                            'total_samples': len(service_data)
                        }
                
                summary['scenarios'][scenario_name] = scenario_summary
        
        # Save summary
        summary_file = f"{self.output_dir}/research_summary_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)
        
        print(f"📊 Summary report saved to {summary_file}")
        return summary

def main():
    parser = argparse.ArgumentParser(description='Research data collector for energy-aware autoscaling')
    parser.add_argument('--mode', choices=['baseline', 'experiment', 'summary'], 
                       required=True, help='Data collection mode')
    parser.add_argument('--scenario', help='Experiment scenario name (for experiment mode)')
    parser.add_argument('--duration', type=int, default=10, 
                       help='Collection duration in minutes')
    parser.add_argument('--prometheus-url', default='http://192.168.49.2:30000',
                       help='Prometheus URL')
    
    args = parser.parse_args()
    
    collector = ResearchDataCollector(args.prometheus_url)
    
    if args.mode == 'baseline':
        collector.collect_baseline_metrics(args.duration)
    elif args.mode == 'experiment':
        if not args.scenario:
            print("Error: --scenario is required for experiment mode")
            return
        collector.collect_experiment_metrics(args.scenario, args.duration)
    elif args.mode == 'summary':
        # Find all CSV files in the output directory
        csv_files = [f for f in os.listdir(collector.output_dir) if f.endswith('.csv')]
        full_paths = [os.path.join(collector.output_dir, f) for f in csv_files]
        collector.generate_summary_report(full_paths)

if __name__ == "__main__":
    main()
