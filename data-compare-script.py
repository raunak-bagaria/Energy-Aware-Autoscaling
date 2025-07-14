#!/usr/bin/env python3
# Install required packages
!pip install pandas matplotlib seaborn numpy -q

# Import necessary libraries
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import os
import glob
from matplotlib.ticker import FuncFormatter
from google.colab import files
import io

# Set plotting style
plt.style.use('seaborn-v0_8')
sns.set_palette("husl")
plt.rcParams['figure.figsize'] = (12, 8)
plt.rcParams['font.size'] = 12

class AutoscalingMetricsAnalyzer:
    def __init__(self):
        """Initialize the analyzer for Colab environment"""
        self.metrics = {}
        self.results_dir = './results'
        self.uploaded_files = []
        
        # Create results directory if it doesn't exist
        if not os.path.exists(self.results_dir):
            os.makedirs(self.results_dir)
            
        # Set up workload scenarios
        self.workloads = ['constant_medium', 'burst', 'cpu_intensive']
        self.approaches = ['baseline', 'cpu_hpa', 'energy_aware']
        
        # Set up colors for consistent visualization
        self.colors = {
            'cpu_hpa': '#1f77b4',       # blue
            'energy_aware': '#2ca02c',   # green
            'baseline': '#d62728'        # red
        }
        
    def upload_files(self):
        """Upload CSV files for analysis using Colab's upload feature"""
        print("📁 Please upload your CSV metrics files...")
        print("(Select all your cpu_hpa_* and energy_aware_* files)")
        
        uploaded = files.upload()
        
        if not uploaded:
            print("❌ No files uploaded")
            return False
        
        self.uploaded_files = list(uploaded.keys())
        print(f"✅ Uploaded {len(self.uploaded_files)} files: {', '.join(self.uploaded_files)}")
        return True
    
    def load_data(self):
        """Load all uploaded CSV metric files into dataframes"""
        print("🔍 Loading metric data files...")
        
        # Use uploaded files
        if not self.uploaded_files:
            print("❌ No files have been uploaded. Please run upload_files() first.")
            return False
        
        # Initialize dictionaries for each workload and approach
        for workload in self.workloads:
            self.metrics[workload] = {}
            for approach in self.approaches:
                self.metrics[workload][approach] = None
        
        # Load each file into the appropriate dictionary entry
        for file_name in self.uploaded_files:
            # Skip any non-metrics files
            if not 'metrics' in file_name:
                print(f"⚠️ Skipping {file_name} - doesn't appear to be a metrics file")
                continue
                
            # Parse approach and workload from filename
            matched = False
            for approach in self.approaches:
                if approach in file_name:
                    for workload in self.workloads:
                        if workload in file_name:
                            try:
                                df = pd.read_csv(file_name)
                                self.metrics[workload][approach] = df
                                print(f"✅ Loaded {approach} {workload} data from {file_name}")
                                matched = True
                            except Exception as e:
                                print(f"❌ Error loading {file_name}: {e}")
            
            if not matched:
                print(f"⚠️ Could not match {file_name} to any workload/approach combination")
        
        # Verify we loaded at least some data
        data_loaded = False
        for workload in self.workloads:
            for approach in self.approaches:
                if self.metrics[workload][approach] is not None:
                    data_loaded = True
        
        if data_loaded:
            print("✅ Data loading complete")
            return True
        else:
            print("❌ No matching data files were loaded")
            return False
        
    def preprocess_data(self):
        """Clean and preprocess the data for analysis"""
        print("🔧 Preprocessing data...")
        
        for workload in self.workloads:
            for approach in self.approaches:
                if self.metrics[workload][approach] is not None:
                    df = self.metrics[workload][approach]
                    
                    # Convert timestamp to datetime
                    df['timestamp'] = pd.to_datetime(df['timestamp'])
                    
                    # Add approach column for easy identification when data is combined
                    df['approach'] = approach
                    
                    # Calculate time elapsed in minutes from first timestamp
                    first_time = df['timestamp'].min()
                    df['minutes_elapsed'] = (df['timestamp'] - first_time).dt.total_seconds() / 60
                    
                    # Store the processed data back
                    self.metrics[workload][approach] = df
                    
        print("✅ Preprocessing complete")
        
    def generate_epr_graph(self):
        """Generate Energy Per Request comparison graph for all workloads"""
        print("📊 Generating EPR comparison graphs...")
        
        # Create figure with three subplots (one per workload)
        fig, axes = plt.subplots(1, 3, figsize=(18, 6))
        fig.suptitle('Energy Per Request (EPR) Comparison Across Workloads', fontsize=16)
        
        for i, workload in enumerate(self.workloads):
            ax = axes[i]
            ax.set_title(f"{workload.replace('_', ' ').title()} Workload")
            ax.set_xlabel('Time (minutes)')
            ax.set_ylabel('EPR (Joules/Request)')
            
            for approach in self.approaches:
                if self.metrics[workload][approach] is not None:
                    df = self.metrics[workload][approach]
                    
                    # Get data for service s1 (which has highest computational complexity)
                    s1_data = df[df['service'] == 's1']
                    
                    ax.plot(s1_data['minutes_elapsed'], 
                            s1_data['epr_joules_per_request'], 
                            label=approach.replace('_', ' ').title(),
                            color=self.colors[approach],
                            marker='o' if approach == 'energy_aware' else 's',
                            linestyle='-' if approach == 'energy_aware' else '--',
                            alpha=0.8)
            
            ax.grid(True, alpha=0.3)
            ax.legend()
            
            # Format y-axis to show fewer decimal places
            ax.yaxis.set_major_formatter(FuncFormatter(lambda x, _: f'{x:.1f}'))
            
        plt.tight_layout(rect=[0, 0, 1, 0.95])  # Adjust layout to make room for suptitle
        plt.savefig(os.path.join(self.results_dir, 'epr_comparison.png'), dpi=300)
        print(f"✅ EPR graph saved")
        plt.show()  # Display in notebook
        plt.close()
        
    def generate_efficiency_graph(self):
        """Generate Efficiency comparison graph for all workloads"""
        print("📊 Generating Efficiency comparison graphs...")
        
        # Create figure with three subplots (one per workload)
        fig, axes = plt.subplots(1, 3, figsize=(18, 6))
        fig.suptitle('Efficiency (RPS/Watt) Comparison Across Workloads', fontsize=16)
        
        for i, workload in enumerate(self.workloads):
            ax = axes[i]
            ax.set_title(f"{workload.replace('_', ' ').title()} Workload")
            ax.set_xlabel('Time (minutes)')
            ax.set_ylabel('Efficiency (RPS/Watt)')
            
            for approach in self.approaches:
                if self.metrics[workload][approach] is not None:
                    df = self.metrics[workload][approach]
                    
                    # Get average across all services (since efficiency is a system-wide metric)
                    grouped = df.groupby(['timestamp']).agg({
                        'minutes_elapsed': 'first',
                        'efficiency_rps_per_watt': 'mean'
                    }).reset_index()
                    
                    ax.plot(grouped['minutes_elapsed'], 
                            grouped['efficiency_rps_per_watt'], 
                            label=approach.replace('_', ' ').title(),
                            color=self.colors[approach],
                            marker='o' if approach == 'energy_aware' else 's',
                            linestyle='-' if approach == 'energy_aware' else '--',
                            alpha=0.8)
            
            ax.grid(True, alpha=0.3)
            ax.legend()
            
            # Format y-axis to show fewer decimal places
            ax.yaxis.set_major_formatter(FuncFormatter(lambda x, _: f'{x:.3f}'))
            
        plt.tight_layout(rect=[0, 0, 1, 0.95])  # Adjust layout to make room for suptitle
        plt.savefig(os.path.join(self.results_dir, 'efficiency_comparison.png'), dpi=300)
        print(f"✅ Efficiency graph saved")
        plt.show()  # Display in notebook
        plt.close()
        
    def generate_power_graph(self):
        """Generate Power consumption comparison graph for all workloads"""
        print("📊 Generating Power consumption comparison graphs...")
        
        # Create figure with three subplots (one per workload)
        fig, axes = plt.subplots(1, 3, figsize=(18, 6))
        fig.suptitle('Power Consumption (Watts) Comparison Across Workloads', fontsize=16)
        
        for i, workload in enumerate(self.workloads):
            ax = axes[i]
            ax.set_title(f"{workload.replace('_', ' ').title()} Workload")
            ax.set_xlabel('Time (minutes)')
            ax.set_ylabel('Power Consumption (Watts)')
            
            for approach in self.approaches:
                if self.metrics[workload][approach] is not None:
                    df = self.metrics[workload][approach]
                    
                    # Get total power across all services
                    grouped = df.groupby(['timestamp']).agg({
                        'minutes_elapsed': 'first',
                        'power_watts': 'sum'
                    }).reset_index()
                    
                    ax.plot(grouped['minutes_elapsed'], 
                            grouped['power_watts'], 
                            label=approach.replace('_', ' ').title(),
                            color=self.colors[approach],
                            marker='o' if approach == 'energy_aware' else 's',
                            linestyle='-' if approach == 'energy_aware' else '--',
                            alpha=0.8)
            
            ax.grid(True, alpha=0.3)
            ax.legend()
            
            # Format y-axis to show fewer decimal places
            ax.yaxis.set_major_formatter(FuncFormatter(lambda x, _: f'{x:.1f}'))
            
        plt.tight_layout(rect=[0, 0, 1, 0.95])  # Adjust layout to make room for suptitle
        plt.savefig(os.path.join(self.results_dir, 'power_comparison.png'), dpi=300)
        print(f"✅ Power graph saved")
        plt.show()  # Display in notebook
        plt.close()
        
    def generate_combined_metrics_graph(self):
        """Generate a combined graph showing EPR, Power, and Efficiency side by side"""
        print("📊 Generating combined metrics graphs...")
        
        # For each workload, create a figure with 3 subplots (one for each metric)
        for workload in self.workloads:
            fig, axes = plt.subplots(1, 3, figsize=(18, 6))
            fig.suptitle(f'Performance Metrics for {workload.replace("_", " ").title()} Workload', fontsize=16)
            
            # EPR Graph (for s1 service)
            ax1 = axes[0]
            ax1.set_title('Energy Per Request (EPR)')
            ax1.set_xlabel('Time (minutes)')
            ax1.set_ylabel('EPR (Joules/Request)')
            
            # Efficiency Graph (system average)
            ax2 = axes[1]
            ax2.set_title('Efficiency (RPS/Watt)')
            ax2.set_xlabel('Time (minutes)')
            ax2.set_ylabel('Efficiency (RPS/Watt)')
            
            # Power Graph (total system)
            ax3 = axes[2]
            ax3.set_title('Power Consumption')
            ax3.set_xlabel('Time (minutes)')
            ax3.set_ylabel('Power (Watts)')
            
            for approach in self.approaches:
                if self.metrics[workload][approach] is not None:
                    df = self.metrics[workload][approach]
                    
                    # EPR for s1 service
                    s1_data = df[df['service'] == 's1']
                    ax1.plot(s1_data['minutes_elapsed'], 
                            s1_data['epr_joules_per_request'], 
                            label=approach.replace('_', ' ').title(),
                            color=self.colors[approach],
                            marker='o' if approach == 'energy_aware' else 's',
                            linestyle='-' if approach == 'energy_aware' else '--',
                            alpha=0.8)
                    
                    # Efficiency - system average
                    grouped_eff = df.groupby(['timestamp']).agg({
                        'minutes_elapsed': 'first',
                        'efficiency_rps_per_watt': 'mean'
                    }).reset_index()
                    ax2.plot(grouped_eff['minutes_elapsed'], 
                            grouped_eff['efficiency_rps_per_watt'], 
                            label=approach.replace('_', ' ').title(),
                            color=self.colors[approach],
                            marker='o' if approach == 'energy_aware' else 's',
                            linestyle='-' if approach == 'energy_aware' else '--',
                            alpha=0.8)
                    
                    # Power - system total
                    grouped_power = df.groupby(['timestamp']).agg({
                        'minutes_elapsed': 'first',
                        'power_watts': 'sum'
                    }).reset_index()
                    ax3.plot(grouped_power['minutes_elapsed'], 
                            grouped_power['power_watts'], 
                            label=approach.replace('_', ' ').title(),
                            color=self.colors[approach],
                            marker='o' if approach == 'energy_aware' else 's',
                            linestyle='-' if approach == 'energy_aware' else '--',
                            alpha=0.8)
            
            # Add legends and grid
            for ax in axes:
                ax.grid(True, alpha=0.3)
                ax.legend()
            
            plt.tight_layout(rect=[0, 0, 1, 0.95])
            plt.savefig(os.path.join(self.results_dir, f'{workload}_combined_metrics.png'), dpi=300)
            print(f"✅ Combined metrics graph for {workload} saved")
            plt.show()  # Display in notebook
            plt.close()
        
    def calculate_summary_statistics(self):
        """Calculate and print summary statistics for each workload and approach"""
        print("📊 Calculating summary statistics...")
        
        # Create a summary table
        summary_data = []
        
        for workload in self.workloads:
            for approach in self.approaches:
                if self.metrics[workload][approach] is not None:
                    df = self.metrics[workload][approach]
                    
                    # Calculate statistics
                    avg_epr = df[df['service'] == 's1']['epr_joules_per_request'].mean()
                    avg_eff = df['efficiency_rps_per_watt'].mean()
                    avg_power = df['power_watts'].sum() / len(df['timestamp'].unique())
                    avg_replicas = df.groupby('service')['replicas'].mean()
                    
                    # Store in summary data
                    summary_row = {
                        'Workload': workload.replace('_', ' ').title(),
                        'Approach': approach.replace('_', ' ').title(),
                        'Avg EPR (J/req)': round(avg_epr, 2),
                        'Avg Efficiency (RPS/W)': round(avg_eff, 4),
                        'Avg Total Power (W)': round(avg_power, 2),
                    }
                    
                    # Add replica counts
                    for service in ['s0', 's1', 's2', 's3']:
                        if service in avg_replicas:
                            summary_row[f'{service} Replicas'] = round(avg_replicas[service], 1)
                        else:
                            summary_row[f'{service} Replicas'] = 'N/A'
                    
                    summary_data.append(summary_row)
        
        # Convert to DataFrame
        summary_df = pd.DataFrame(summary_data)
        
        # Save as CSV
        summary_csv_path = os.path.join(self.results_dir, 'summary_statistics.csv')
        summary_df.to_csv(summary_csv_path, index=False)
        print(f"✅ Summary statistics saved as CSV")
        
        # Print summary to console and display in notebook
        print("\n📊 SUMMARY STATISTICS\n" + "="*50)
        display(summary_df)
        
        # Return the summary for further analysis
        return summary_df
        
    def run_all_analyses(self):
        """Run all analyses in sequence"""
        self.preprocess_data()
        self.generate_epr_graph()
        self.generate_efficiency_graph()
        self.generate_power_graph()
        self.generate_combined_metrics_graph()
        summary = self.calculate_summary_statistics()
        
        print("\n✅ All analyses complete!")
        
        # Offer to download all generated files
        print("\n📥 Would you like to download all results? (y/n)")
        if input().strip().lower() == 'y':
            print("Preparing downloads...")
            for file_path in glob.glob(os.path.join(self.results_dir, '*')):
                files.download(file_path)
        
        return summary

# Run the analysis
print("📊 Autoscaling Metrics Analysis Tool - Colab Version")
print("=" * 60)
print("This script will analyze your muBench energy-aware autoscaling metrics")
print("and generate comparison graphs and tables.")

# Create the analyzer
analyzer = AutoscalingMetricsAnalyzer()

# Step 1: Upload files
print("\nSTEP 1: Upload your metrics CSV files")
if analyzer.upload_files():
    # Step 2: Load the data
    print("\nSTEP 2: Loading data files")
    if analyzer.load_data():
        # Step 3: Run all analyses
        print("\nSTEP 3: Running analyses")
        analyzer.run_all_analyses()
    else:
        print("❌ Data loading failed. Please check your uploaded files.")
else:
    print("❌ File upload failed. Please try again.")
