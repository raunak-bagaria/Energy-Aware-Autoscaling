#!/usr/bin/env python3
"""
Load testing script for energy-aware autoscaling experiments
"""

import requests
import time
import json
import threading
import random
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor
import argparse

class LoadTester:
    def __init__(self, gateway_url, services, duration=300):
        self.gateway_url = gateway_url
        self.services = services
        self.duration = duration
        self.results = {
            'total_requests': 0,
            'successful_requests': 0,
            'failed_requests': 0,
            'response_times': [],
            'start_time': None,
            'end_time': None
        }
        self.running = False
        
    def send_request(self, service):
        """Send a single request to a service"""
        try:
            start_time = time.time()
            response = requests.get(f"{self.gateway_url}/{service}", timeout=10)
            end_time = time.time()
            
            response_time = (end_time - start_time) * 1000  # Convert to milliseconds
            
            if response.status_code == 200:
                self.results['successful_requests'] += 1
            else:
                self.results['failed_requests'] += 1
                
            self.results['response_times'].append(response_time)
            self.results['total_requests'] += 1
            
            return response_time
            
        except Exception as e:
            self.results['failed_requests'] += 1
            self.results['total_requests'] += 1
            return None
    
    def workload_pattern_constant(self, rps, service='s0'):
        """Generate constant load at specified RPS"""
        interval = 1.0 / rps
        while self.running:
            self.send_request(service)
            time.sleep(interval)
    
    def workload_pattern_burst(self, base_rps, burst_rps, burst_duration, service='s0'):
        """Generate bursty load pattern"""
        burst_interval = 1.0 / burst_rps
        normal_interval = 1.0 / base_rps
        
        while self.running:
            # Normal load for 30 seconds
            normal_start = time.time()
            while time.time() - normal_start < 30 and self.running:
                self.send_request(service)
                time.sleep(normal_interval)
            
            # Burst load for specified duration
            if self.running:
                burst_start = time.time()
                while time.time() - burst_start < burst_duration and self.running:
                    self.send_request(service)
                    time.sleep(burst_interval)
    
    def workload_pattern_mixed_services(self, rps):
        """Generate load across multiple services"""
        interval = 1.0 / rps
        while self.running:
            service = random.choice(self.services)
            self.send_request(service)
            time.sleep(interval)
    
    def cpu_intensive_workload(self, rps, service='s0'):
        """Generate CPU-intensive workload (targets compute_pi function)"""
        interval = 1.0 / rps
        while self.running:
            # The compute_pi function will stress CPU
            self.send_request(service)
            time.sleep(interval)
    
    def run_experiment(self, workload_type='constant', **kwargs):
        """Run a specific workload experiment"""
        print(f"🚀 Starting {workload_type} workload experiment...")
        print(f"📊 Duration: {self.duration} seconds")
        print(f"🎯 Target services: {self.services}")
        print(f"⏰ Start time: {datetime.now()}")
        
        self.results['start_time'] = datetime.now()
        self.running = True
        
        # Choose workload pattern
        if workload_type == 'constant':
            rps = kwargs.get('rps', 5)
            service = kwargs.get('service', 's0')
            print(f"📈 Constant load: {rps} RPS to {service}")
            workload_thread = threading.Thread(
                target=self.workload_pattern_constant, 
                args=(rps, service)
            )
            
        elif workload_type == 'burst':
            base_rps = kwargs.get('base_rps', 2)
            burst_rps = kwargs.get('burst_rps', 20)
            burst_duration = kwargs.get('burst_duration', 10)
            service = kwargs.get('service', 's0')
            print(f"💥 Burst load: {base_rps} RPS baseline, {burst_rps} RPS bursts for {burst_duration}s")
            workload_thread = threading.Thread(
                target=self.workload_pattern_burst,
                args=(base_rps, burst_rps, burst_duration, service)
            )
            
        elif workload_type == 'mixed':
            rps = kwargs.get('rps', 10)
            print(f"🔀 Mixed services load: {rps} RPS across all services")
            workload_thread = threading.Thread(
                target=self.workload_pattern_mixed_services,
                args=(rps,)
            )
            
        elif workload_type == 'cpu_intensive':
            rps = kwargs.get('rps', 5)
            service = kwargs.get('service', 's0')
            print(f"🔥 CPU-intensive load: {rps} RPS to {service}")
            workload_thread = threading.Thread(
                target=self.cpu_intensive_workload,
                args=(rps, service)
            )
        
        # Start workload
        workload_thread.start()
        
        # Monitor progress
        start_time = time.time()
        while time.time() - start_time < self.duration:
            elapsed = time.time() - start_time
            remaining = self.duration - elapsed
            print(f"⏳ Progress: {elapsed:.1f}s / {self.duration}s | "
                  f"Requests: {self.results['total_requests']} | "
                  f"Success rate: {self.get_success_rate():.1f}%")
            time.sleep(10)
        
        # Stop workload
        self.running = False
        workload_thread.join()
        self.results['end_time'] = datetime.now()
        
        print("✅ Experiment completed!")
        self.print_summary()
    
    def get_success_rate(self):
        """Calculate success rate percentage"""
        if self.results['total_requests'] == 0:
            return 0
        return (self.results['successful_requests'] / self.results['total_requests']) * 100
    
    def get_avg_response_time(self):
        """Calculate average response time"""
        if not self.results['response_times']:
            return 0
        return sum(self.results['response_times']) / len(self.results['response_times'])
    
    def get_percentile(self, percentile):
        """Calculate response time percentile"""
        if not self.results['response_times']:
            return 0
        sorted_times = sorted(self.results['response_times'])
        index = int(len(sorted_times) * percentile / 100) - 1
        return sorted_times[max(0, index)]
    
    def print_summary(self):
        """Print experiment summary"""
        duration = (self.results['end_time'] - self.results['start_time']).total_seconds()
        avg_rps = self.results['total_requests'] / duration if duration > 0 else 0
        
        print(f"\n{'='*60}")
        print(f"LOAD TEST SUMMARY")
        print(f"{'='*60}")
        print(f"Duration: {duration:.1f} seconds")
        print(f"Total requests: {self.results['total_requests']}")
        print(f"Successful requests: {self.results['successful_requests']}")
        print(f"Failed requests: {self.results['failed_requests']}")
        print(f"Success rate: {self.get_success_rate():.1f}%")
        print(f"Average RPS: {avg_rps:.2f}")
        print(f"Average response time: {self.get_avg_response_time():.2f} ms")
        print(f"95th percentile: {self.get_percentile(95):.2f} ms")
        print(f"99th percentile: {self.get_percentile(99):.2f} ms")
        print(f"{'='*60}")

def main():
    parser = argparse.ArgumentParser(description='Load tester for energy-aware autoscaling experiments')
    parser.add_argument('--gateway', default='http://localhost:31113', 
                       help='muBench API gateway URL')
    parser.add_argument('--duration', type=int, default=300,
                       help='Test duration in seconds')
    parser.add_argument('--workload', choices=['constant', 'burst', 'mixed', 'cpu_intensive'],
                       default='constant', help='Workload pattern')
    parser.add_argument('--rps', type=int, default=5,
                       help='Requests per second')
    parser.add_argument('--service', default='s0',
                       help='Target service')
    
    args = parser.parse_args()
    
    # Available services in muBench
    services = [f's{i}' for i in range(10)]
    
    # Create load tester
    tester = LoadTester(args.gateway, services, args.duration)
    
    # Run experiment based on workload type
    if args.workload == 'constant':
        tester.run_experiment('constant', rps=args.rps, service=args.service)
    elif args.workload == 'burst':
        tester.run_experiment('burst', base_rps=2, burst_rps=args.rps, 
                             burst_duration=10, service=args.service)
    elif args.workload == 'mixed':
        tester.run_experiment('mixed', rps=args.rps)
    elif args.workload == 'cpu_intensive':
        tester.run_experiment('cpu_intensive', rps=args.rps, service=args.service)

if __name__ == "__main__":
    main()
