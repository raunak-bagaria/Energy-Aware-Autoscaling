1. Check if `kubectl top pods works`. If it does, proceed to step 4. 

2. Install metrics server
```zsh
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

3. Patch metrics server for container/minikube environment
```zsh
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"},
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname"}
]'
```

4. Add CPU resource requests to all services
```zsh
kubectl patch deployment s0 -p '{"spec":{"template":{"spec":{"containers":[{"name":"s0","resources":{"requests":{"cpu":"100m","memory":"128Mi"},"limits":{"cpu":"1000m","memory":"512Mi"}}}]}}}}'

kubectl patch deployment s1 -p '{"spec":{"template":{"spec":{"containers":[{"name":"s1","resources":{"requests":{"cpu":"100m","memory":"128Mi"},"limits":{"cpu":"1000m","memory":"512Mi"}}}]}}}}'

kubectl patch deployment s2 -p '{"spec":{"template":{"spec":{"containers":[{"name":"s2","resources":{"requests":{"cpu":"100m","memory":"128Mi"},"limits":{"cpu":"1000m","memory":"512Mi"}}}]}}}}'

kubectl patch deployment s3 -p '{"spec":{"template":{"spec":{"containers":[{"name":"s3","resources":{"requests":{"cpu":"100m","memory":"128Mi"},"limits":{"cpu":"1000m","memory":"512Mi"}}}]}}}}'
```

5. Wait for pods to restart, then run:
```zsh
kubectl get pods
kubectl get hpa
```