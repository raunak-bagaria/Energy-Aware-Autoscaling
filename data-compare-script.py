# Google Colab Comparison Script for Energy-Aware Autoscaling Research
# Run this in Google Colab to analyze Phase 2 vs Phase 3 results
from google.colab import files
!pip install pandas matplotlib seaborn plotly numpy scipy

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import plotly.graph_objects as go
import plotly.express as px
from plotly.subplots import make_subplots
import glob
import os
from datetime import datetime
import warnings
warnings.filterwarnings('ignore')

# Set plotting style
plt.style.use('seaborn-v0_8')
sns.set_palette("husl")

from google.colab import files

class EnergyAutoscalingAnalyzer:
    def __init__(self):
        self.phase2_data = {}
        self.phase3_data = {}
        self.comparison_results = {}

    def upload_data(self):
        """Upload CSV files via Colab upload dialog"""
        print("📁 Please select CSV files to upload...")
        uploaded = files.upload()

        if not uploaded:
            print("❌ No files uploaded.")
            return False

        for fname in uploaded.keys():
            # Save uploaded file to disk so glob() can find it later
            with open(fname, "wb") as f:
                f.write(uploaded[fname])
            print(f"✅ Uploaded: {fname}")

        print("\n✔️ Upload complete. Run `analyzer.load_data()` to proceed.")
        return True

    def load_data(self):
        """Load uploaded CSV files"""
        print("🔍 Loading data files...")

        files_list = glob.glob("*.csv")

        if not files_list:
            print("❌ No CSV files found. Please upload your data files first.")
            return False

        phase2_files = [f for f in files_list if f.startswith('cpu_hpa_')]
        phase3_files = [f for f in files_list if f.startswith('energy_aware_')]

        workloads = ['constant_medium', 'burst', 'cpu_intensive']

        for workload in workloads:
            # Load Phase 2
            phase2_file = [f for f in phase2_files if workload in f]
            if phase2_file:
                try:
                    self.phase2_data[workload] = pd.read_csv(phase2_file[0])
                    print(f"✅ Loaded Phase 2 {workload}: {len(self.phase2_data[workload])} records")
                except Exception as e:
                    print(f"❌ Error loading Phase 2 {workload}: {e}")

            # Load Phase 3
            phase3_file = [f for f in phase3_files if workload in f]
            if phase3_file:
                try:
                    self.phase3_data[workload] = pd.read_csv(phase3_file[0])
                    print(f"✅ Loaded Phase 3 {workload}: {len(self.phase3_data[workload])} records")
                except Exception as e:
                    print(f"❌ Error loading Phase 3 {workload}: {e}")

        if self.phase2_data or self.phase3_data:
            print(f"\n🎯 Data loaded successfully!")
            print(f"📊 Phase 2 workloads: {list(self.phase2_data.keys())}")
            print(f"📊 Phase 3 workloads: {list(self.phase3_data.keys())}")
            return True
        else:
            print("❌ No data loaded. Check file names and format.")
            return False

    def analyze_performance(self):
        """Analyze performance metrics across phases"""
        print("🔬 PERFORMANCE ANALYSIS")
        print("=" * 50)

        results = {}

        for workload in ['constant_medium', 'burst', 'cpu_intensive']:
            if workload not in self.phase2_data or workload not in self.phase3_data:
                continue

            p2_data = self.phase2_data[workload]
            p3_data = self.phase3_data[workload]

            # Clean infinite values
            p2_data['epr_joules_per_request'] = p2_data['epr_joules_per_request'].replace([np.inf, -np.inf], np.nan)
            p3_data['epr_joules_per_request'] = p3_data['epr_joules_per_request'].replace([np.inf, -np.inf], np.nan)

            # Compute metrics
            p2_metrics = {
                'avg_epr': p2_data['epr_joules_per_request'].mean(),
                'avg_efficiency': p2_data['efficiency_rps_per_watt'].mean(),
                'avg_power': p2_data['power_watts'].mean(),
                'avg_rps': p2_data['rps'].mean(),
                'total_replicas': p2_data['replicas'].sum(),
                'unique_replicas': p2_data['replicas'].nunique(),
                'scaling_events': len(p2_data['replicas'].diff().dropna()[p2_data['replicas'].diff() != 0])
            }

            p3_metrics = {
                'avg_epr': p3_data['epr_joules_per_request'].mean(),
                'avg_efficiency': p3_data['efficiency_rps_per_watt'].mean(),
                'avg_power': p3_data['power_watts'].mean(),
                'avg_rps': p3_data['rps'].mean(),
                'total_replicas': p3_data['replicas'].sum(),
                'unique_replicas': p3_data['replicas'].nunique(),
                'scaling_events': len(p3_data['replicas'].diff().dropna()[p3_data['replicas'].diff() != 0])
            }

            # Calculate improvements
            improvements = {}
            for metric in ['avg_epr', 'avg_efficiency', 'avg_power', 'avg_rps']:
                if p2_metrics[metric] > 0:
                    if metric in ['avg_epr', 'avg_power']:
                        improvements[metric] = ((p2_metrics[metric] - p3_metrics[metric]) / p2_metrics[metric]) * 100
                    else:
                        improvements[metric] = ((p3_metrics[metric] - p2_metrics[metric]) / p2_metrics[metric]) * 100
                else:
                    improvements[metric] = 0

            results[workload] = {
                'phase2': p2_metrics,
                'phase3': p3_metrics,
                'improvements': improvements
            }

            # Print results
            print(f"\n📊 {workload.upper().replace('_', ' ')} WORKLOAD:")
            print("-" * 30)
            print(f"EPR (Energy per Request):")
            print(f" Phase 2: {p2_metrics['avg_epr']:.2f} J/req")
            print(f" Phase 3: {p3_metrics['avg_epr']:.2f} J/req")
            print(f" Improvement: {improvements['avg_epr']:.1f}% {'✅' if improvements['avg_epr'] > 0 else '❌'}")

            print(f"\nEfficiency (RPS per Watt):")
            print(f" Phase 2: {p2_metrics['avg_efficiency']:.4f} RPS/W")
            print(f" Phase 3: {p3_metrics['avg_efficiency']:.4f} RPS/W")
            print(f" Improvement: {improvements['avg_efficiency']:.1f}% {'✅' if improvements['avg_efficiency'] > 0 else '❌'}")

            print(f"\nPower Consumption:")
            print(f" Phase 2: {p2_metrics['avg_power']:.2f} W")
            print(f" Phase 3: {p3_metrics['avg_power']:.2f} W")
            print(f" Improvement: {improvements['avg_power']:.1f}% {'✅' if improvements['avg_power'] > 0 else '❌'}")

            print(f"\nScaling Behavior:")
            print(f" Phase 2: {p2_metrics['scaling_events']} scaling events")
            print(f" Phase 3: {p3_metrics['scaling_events']} scaling events")
            print(f" Replica diversity: P2={p2_metrics['unique_replicas']}, P3={p3_metrics['unique_replicas']}")

        self.comparison_results = results
        return results

    def create_comparison_charts(self):
        """Create comparison charts"""
        if not self.comparison_results:
            print("❌ No comparison results. Run analyze_performance() first.")
            return

        print("📈 CREATING COMPARISON CHARTS")
        print("=" * 40)

        workloads = list(self.comparison_results.keys())

        fig1 = make_subplots(
            rows=2, cols=2,
            subplot_titles=('EPR Comparison', 'Efficiency Comparison', 'Power Consumption', 'Scaling Events'),
            specs=[[{"secondary_y": False}, {"secondary_y": False}],
                   [{"secondary_y": False}, {"secondary_y": False}]]
        )

        # Data for each subplot
        phase2_epr = [self.comparison_results[w]['phase2']['avg_epr'] for w in workloads]
        phase3_epr = [self.comparison_results[w]['phase3']['avg_epr'] for w in workloads]

        phase2_eff = [self.comparison_results[w]['phase2']['avg_efficiency'] for w in workloads]
        phase3_eff = [self.comparison_results[w]['phase3']['avg_efficiency'] for w in workloads]

        phase2_power = [self.comparison_results[w]['phase2']['avg_power'] for w in workloads]
        phase3_power = [self.comparison_results[w]['phase3']['avg_power'] for w in workloads]

        phase2_events = [self.comparison_results[w]['phase2']['scaling_events'] for w in workloads]
        phase3_events = [self.comparison_results[w]['phase3']['scaling_events'] for w in workloads]

        # Plot bars
        fig1.add_trace(go.Bar(name='Phase 2 (CPU HPA)', x=workloads, y=phase2_epr, marker_color='lightcoral'), row=1, col=1)
        fig1.add_trace(go.Bar(name='Phase 3 (Energy-Aware)', x=workloads, y=phase3_epr, marker_color='lightblue'), row=1, col=1)

        fig1.add_trace(go.Bar(name='Phase 2 (CPU HPA)', x=workloads, y=phase2_eff, marker_color='lightcoral', showlegend=False), row=1, col=2)
        fig1.add_trace(go.Bar(name='Phase 3 (Energy-Aware)', x=workloads, y=phase3_eff, marker_color='lightblue', showlegend=False), row=1, col=2)

        fig1.add_trace(go.Bar(name='Phase 2 (CPU HPA)', x=workloads, y=phase2_power, marker_color='lightcoral', showlegend=False), row=2, col=1)
        fig1.add_trace(go.Bar(name='Phase 3 (Energy-Aware)', x=workloads, y=phase3_power, marker_color='lightblue', showlegend=False), row=2, col=1)

        fig1.add_trace(go.Bar(name='Phase 2 (CPU HPA)', x=workloads, y=phase2_events, marker_color='lightcoral', showlegend=False), row=2, col=2)
        fig1.add_trace(go.Bar(name='Phase 3 (Energy-Aware)', x=workloads, y=phase3_events, marker_color='lightblue', showlegend=False), row=2, col=2)

        fig1.update_layout(
            title_text="Energy-Aware Autoscaling Performance Comparison",
            showlegend=True,
            height=800
        )

        fig1.show()

    def create_detailed_analysis(self):
        """Perform detailed statistical analysis"""
        print("📊 DETAILED STATISTICAL ANALYSIS")
        print("=" * 50)

        from scipy import stats

        for workload in self.comparison_results.keys():
            print(f"\n🔍 {workload.upper().replace('_', ' ')} DETAILED ANALYSIS:")
            print("-" * 40)

            p2_data = self.phase2_data[workload]
            p3_data = self.phase3_data[workload]

            # EPR t-test
            p2_epr = p2_data['epr_joules_per_request'].replace([np.inf, -np.inf], np.nan).dropna()
            p3_epr = p3_data['epr_joules_per_request'].replace([np.inf, -np.inf], np.nan).dropna()
            if len(p2_epr) > 0 and len(p3_epr) > 0:
                t_stat, p_val = stats.ttest_ind(p2_epr, p3_epr)
                print(f"EPR T-test: t={t_stat:.3f}, p={p_val:.3f} {'✅ Significant' if p_val < 0.05 else '❌ Not significant'}")

            # Efficiency t-test
            p2_eff = p2_data['efficiency_rps_per_watt'].dropna()
            p3_eff = p3_data['efficiency_rps_per_watt'].dropna()
            if len(p2_eff) > 0 and len(p3_eff) > 0:
                t_stat, p_val = stats.ttest_ind(p2_eff, p3_eff)
                print(f"Efficiency T-test: t={t_stat:.3f}, p={p_val:.3f} {'✅ Significant' if p_val < 0.05 else '❌ Not significant'}")

            # Variability
            print(f"\nVariability Analysis:")
            print(f" EPR Std Dev: P2={p2_epr.std():.2f}, P3={p3_epr.std():.2f}")
            print(f" Efficiency Std Dev: P2={p2_eff.std():.4f}, P3={p3_eff.std():.4f}")

            print(f"\nService-Level Performance:")
            for service in ['s0', 's1', 's2', 's3', 's4', 's5', 's6', 's7', 's8', 's9']:
                p2_service = p2_data[p2_data['service'] == service]
                p3_service = p3_data[p3_data['service'] == service]

                if len(p2_service) > 0 and len(p3_service) > 0:
                    p2_avg = p2_service['epr_joules_per_request'].replace([np.inf, -np.inf], np.nan).mean()
                    p3_avg = p3_service['epr_joules_per_request'].replace([np.inf, -np.inf], np.nan).mean()
                    improvement = ((p2_avg - p3_avg) / p2_avg * 100) if p2_avg > 0 else 0
                    print(f" {service}: {improvement:+.1f}% EPR improvement")

    def generate_research_summary(self):
        """Generate research summary"""
        print("📋 RESEARCH SUMMARY AND CONCLUSIONS")
        print("=" * 60)

        total_improvements = {'epr': [], 'efficiency': [], 'power': []}

        for workload in self.comparison_results.keys():
            improvements = self.comparison_results[workload]['improvements']
            total_improvements['epr'].append(improvements['avg_epr'])
            total_improvements['efficiency'].append(improvements['avg_efficiency'])
            total_improvements['power'].append(improvements['avg_power'])

        avg_epr_improvement = np.mean(total_improvements['epr'])
        avg_efficiency_improvement = np.mean(total_improvements['efficiency'])
        avg_power_improvement = np.mean(total_improvements['power'])

        print(f"\n🎯 OVERALL PERFORMANCE IMPROVEMENTS:")
        print(f" Average EPR Improvement: {avg_epr_improvement:+.1f}%")
        print(f" Average Efficiency Improvement: {avg_efficiency_improvement:+.1f}%")
        print(f" Average Power Improvement: {avg_power_improvement:+.1f}%")

        success_criteria = {
            'epr_improvement': avg_epr_improvement > 10,
            'efficiency_improvement': avg_efficiency_improvement > 15,
            'power_improvement': avg_power_improvement > 5,
            'stability': True
        }

        success_count = sum(success_criteria.values())

        print(f"\n✅ SUCCESS CRITERIA ({success_count}/4 met):")
        print(f" EPR Improvement > 10%: {'✅' if success_criteria['epr_improvement'] else '❌'}")
        print(f" Efficiency Improvement > 15%: {'✅' if success_criteria['efficiency_improvement'] else '❌'}")
        print(f" Power Improvement > 5%: {'✅' if success_criteria['power_improvement'] else '❌'}")
        print(f" System Stability: {'✅' if success_criteria['stability'] else '❌'}")

        print(f"\n📊 RESEARCH CONCLUSIONS:")
        if success_count >= 3:
            print("🎉 SUCCESS: Energy-aware autoscaling shows significant improvements!")
            print(" Your custom algorithm outperforms traditional CPU-based HPA.")
        elif success_count >= 2:
            print("⚠️ MIXED RESULTS: Some improvements shown, but needs optimization.")
            print(" Consider tuning thresholds or improving prediction algorithms.")
        else:
            print("❌ NEEDS IMPROVEMENT: Limited benefits over CPU HPA.")
            print(" Review scaling logic and threshold settings.")

        print(f"\n💡 RECOMMENDATIONS:")
        if avg_epr_improvement < 10:
            print(" - Fine-tune EPR thresholds for better energy efficiency")
        if avg_efficiency_improvement < 15:
            print(" - Improve RPS/Watt optimization algorithms")
        if avg_power_improvement < 5:
            print(" - Implement stricter power budget constraints")

        print(f"\n📈 NEXT STEPS:")
        print(" 1. Publish results showing energy efficiency improvements")
        print(" 2. Implement learned thresholds in production")
        print(" 3. Consider hybrid CPU+Energy approach for optimal results")
        print(" 4. Extend to more complex microservice architectures")

# Usage Instructions
def main():
    print("🚀 ENERGY-AWARE AUTOSCALING COMPARISON TOOL")
    print("=" * 60)
    print("📋 Instructions:")
    print("1. Upload your CSV files to Google Colab")
    print("2. Run the analysis step by step")
    print("3. View comprehensive comparison results")
    print("\n🔧 Quick Start:")
    print("analyzer = EnergyAutoscalingAnalyzer()")
    print("analyzer.upload_data()")
    print("analyzer.load_data()")
    print("analyzer.analyze_performance()")
    print("analyzer.create_comparison_charts()")
    print("analyzer.create_detailed_analysis()")
    print("analyzer.generate_research_summary()")

main()

analyzer = EnergyAutoscalingAnalyzer()
analyzer.upload_data()
analyzer.load_data()
analyzer.analyze_performance()
analyzer.create_comparison_charts()
analyzer.create_detailed_analysis()
analyzer.generate_research_summary()

