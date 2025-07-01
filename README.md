**Contents**

- [Installation](#installation)
  - [1. Create minikube cluster](#1-create-minikube-cluster)
  - [2. Install µBench in a Docker Container](#2-install-µbench-in-a-docker-container)
  - [3. Install the Monitoring Framework (Prometheus, Grafana, Jaeger, Kiali)](#3-install-the-monitoring-framework-prometheus-grafana-jaeger-kiali)
  - [4. Install Kepler (for monitoring Power metrics)](#4-install-kepler-for-monitoring-power-metrics)
  - [5. Deploy and load the microservices](#5-deploy-and-load-the-microservices)
- [Experimental Workflow](#experimental-workflow)
  - [1. Monitoring and Baseline Measurement](#1-monitoring-and-baseline-measurement)
  - [2. Deploy Energy-Aware HPA](#2-deploy-energy-aware-hpa)
  - [3. Test with different workloads](#3-test-with-different-workloads)

## Installation

### 1. Create minikube cluster

```zsh
minikube config set memory 8192
minikube config set cpus 4

minikube start
```

### 2. Install µBench in a Docker Container

```zsh
docker run -d --name mubench --network minikube msvcbench/mubench
```

It is necessary to provide the container with the .kube/config file to allow accessing the Kubernetes cluster from the container.
In the case of a minikube cluster, you can get the config file from your host with

```zsh
minikube kubectl -config view --flatten > config
```

Open the produced config file : ```nano config```
Set server key as :
```zsh
server : https://192.168.49.2:8443
```
(Verify IP with ```minikube ip```)

Copy the modified config file into the µBench container
```zsh
docker cp config mubench:/root/.kube/config
```

Enter the µBench container :

```zsh
docker exec -it mubench bash
```


### 3. Install the Monitoring Framework (Prometheus, Grafana, Jaeger, Kiali)

Inside the mubench container, run:

```zsh
cd $HOME/muBench/Monitoring/kubernetes-full-monitoring
sh ./monitoring-install.sh
```

Get the URL of the services by running these commands from the host (another terminal outside the mubench container). Each command requires a different terminal window.

```zsh
minikube service -n monitoring prometheus-nodeport
minikube service -n monitoring grafana-nodeport
minikube service -n istio-system jaeger-nodeport
minikube service -n istio-system kiali-nodeport
```

### 4. Install Kepler (for monitoring Power metrics)

Inside mubench container, run :

```zsh
kubectl create ns kepler

helm repo add kepler https://sustainable-computing-io.github.io/kepler-helm-chart/
helm repo update

helm install kepler kepler/kepler -n kepler
```

Check that Kepler pods and services are running:

```zsh
kubectl get pods -n kepler
kubectl get svc -n kepler
```

Verify Kepler Metrics Endpoint (run this OUTSIDE mubench)

```zsh
kubectl proxy
```

Access metrics via browser or curl: http://localhost:8001/api/v1/namespaces/kepler/services/kepler:http/proxy/metrics

You should see Prometheus metrics starting with kepler_container_.

Ensure the Kepler service has the label required by ServiceMonitor:

```zsh
kubectl label svc kepler app.kubernetes.io/name=kepler -n kepler --overwrite
```

Create and Apply ServiceMonitor for Kepler

`kepler-servicemonitor.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kepler-servicemonitor
  namespace: kepler
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: kepler
  namespaceSelector:
    matchNames:
  kepler
  endpoints:
port: http
      path: /metrics
      interval: 15s
```

Apply it:

```zsh
kubectl apply -f kepler-servicemonitor.yaml
```

**Verify Prometheus Scraping**

Open Prometheus UI 
```zsh
minikube service -n monitoring prometheus-nodeport
``` 
Go to **Status > Targets** and look for the kepler target with status `UP`.

**Import Kepler Dashboard into Grafana**

Download the dashboard JSON:

```zsh
curl -fsSL https://raw.githubusercontent.com/sustainable-computing-io/kepler/main/grafana-dashboards/Kepler-Exporter.json -o kepler-dashboard.json
```

Access Grafana UI

```zsh
minikube service -n monitoring grafana-nodeport
```

**Import Dashboard**

Click "+" → Import

Upload `kepler-dashboard.json`

Select your Prometheus data source

Import


### 5. Deploy and load the microservices

```zsh
cd $HOME/muBench
python3 Deployers/K8sDeployer/RunK8sDeployer.py -c Configs/K8sParameters.json

cd $HOME/muBench
python3 Benchmarks/Runner/Runner.py -c Configs/RunnerParameters.json
```

### 6. Get EPR Metrics

#### Note: REMEMBER TO KEEP THE RUNNER RUNNING IN THE BACKGROUND DURING THIS PROCESS

Prometheus needs to be configured to scrape from the right port i.e the port where istio is exporting the metrics. This has to be done for every service running.

A quick way to do this is by patching the deployment for all services using this script. (It can also be done manually by altering YAMLs of each service)

```zsh
for svc in s{0..9}; do
  echo "Patching $svc..."
  kubectl patch deployment $svc -n default --type='json' -p='[
    {"op": "add", "path": "/spec/template/metadata/annotations", "value": {
      "prometheus.io/scrape": "true",
      "prometheus.io/port": "15090",
      "prometheus.io/path": "/stats/prometheus"
    }}
  ]'
done
```

now restart the deployments, re-creating the pods with new annotations.

Verify that the metrics are being scraped by Prometheus by checking the Prometheus UI:
  - run ```zsh minikube service -n monitoring prometheus-nodeport```
  - in the Prometheus UI, go to ``` status -> target health ```
  - check if there is a job or target on port 15090, named ```istio-proxy```, ```envoy-stats``` or ```istio``` and they should have status as ```up```
  - ```istio_requests_total``` should give data when queried in the prometheus UI

### 7. Calculate EPR
based on the labels/tags for the logs being sent to Prometheus, EPR can be calculated using the below formula:
```promql 
(
  sum by (pod_name) (rate(kepler_container_joules_total[1m]))
)
/
(
  sum by (pod_name) (rate(istio_requests_total[1m]))
)
```
This query should give per-service EPR data.



## Experimental Workflow

Throughout this section, Terminal 1 is the terminal inside the mubench container, and Terminal 2 is outside (host terminal).

### 1. Monitoring and Baseline Measurement

Expose Prometheus (from another terminal outside container : Terminal 2)
```zsh
minikube service -n monitoring prometheus-nodeport
```

Run the script in Terminal 1 with the correct Prometheus URL
```zsh
chmod +x energy_monitoring.py

python3 energy_monitoring.py
```

Key Features:
- Energy Per Request (EPR) Calculation: Calculates how much energy (Joules) each service consumes per request
- Power Consumption Monitoring: Tracks real-time power usage via Kepler metrics
- Performance Metrics: Collects latency percentiles (P95, P99), request rates (RPS), replica counts
- Efficiency Analysis: Calculates efficiency scores (RPS per Watt) to identify energy-efficient vs inefficient services
- Anomaly Detection: Flags services with high latency AND high energy consumption

### 2. Deploy Energy-Aware HPA

Terminal 1
```zsh
kubectl apply -f energy-aware-hpa.yaml

# Check if it's working
kubectl get hpa
kubectl describe hpa energy-aware-hpa-s0
```

### 3. Test with different workloads

```zsh
# Get the gateway URL from Terminal 1
kubectl get svc gw-nginx
# Note the NodePort (e.g., 80:31113/TCP)

# Get minikube IP from Terminal 2
minikube ip
# Example output: 192.168.49.2
```

Run load tests with the correct gateway URL and try different workloads (Terminal 1)
```zsh
python3 load_tester.py --gateway http://192.168.49.2:31113 --workload constant --rps 5 --duration 60

python3 load_tester.py --gateway http://192.168.49.2:31113 --workload burst --rps 10 --duration 120

python3 load_tester.py --gateway http://192.168.49.2:31113 --workload cpu_intensive --rps 5 --duration 300
```