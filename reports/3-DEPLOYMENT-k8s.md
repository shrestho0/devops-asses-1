# DevOps Task — Local Kubernetes (`kind`) Deployment, Autoscaling & Rollout Notes

## 0. Operational Notes & TODO

> **(0)** Though the task asked at least 2 replicas, I mis-read/mis-understood and kept min replica to 3 and scaled up to 6. Currently ignoring this part due to shortage of time, but the this is reproducible in the very same way.


---

## 1. Setup

### Control Plane Setup
With port binding host to container port `30080`:

- **Create the cluster:**
  ```bash
  kind create cluster \
    --config k8s/1-kind-config.yml \
    --wait 120s
  ```

- **Verify:**
  ```bash
  kubectl cluster-info --context kind-devops-local
  kubectl get nodes
  ```

### Setting Up the Metrics Server
```bash
helm repo add metrics-server \
  [https://kubernetes-sigs.github.io/metrics-server/](https://kubernetes-sigs.github.io/metrics-server/)

helm repo update

helm upgrade --install metrics-server \
  metrics-server/metrics-server \
  --version 3.14.0 \
  --namespace kube-system \
  --values k8s/helm/metrics-server-values.yml \
  --wait
```

### Build the Docker Image and Verify
```bash
docker build \
  -t devops-task:1.0.0 \
  -f apps/devops-task/Dockerfile \
  apps/devops-task

docker images devops-task
```

### Load Image to `kind`
```bash
kind load docker-image \
  devops-task:1.0.0 \
  --name devops-local
```

- **Verify if the image loaded:**
  ```bash
  docker exec devops-local-control-plane \
    crictl images | grep devops-task
  ```

### Initial Deployment
- Build manifests with: `kubectl kustomize k8s/`
- Rollout deployment: `kubectl apply -k k8s/`

---

## 2. Checking HPA (With CPU Load Generation)

### Load Generation Commands
```bash
kubectl exec -it -n devops-task devops-task-84cc6448b-nlh9b -- sh -c 'yes'
```
and
```bash
wrk -t16 -c200 -d2400s --latency [http://127.0.0.1:30080/](http://127.0.0.1:30080/)
```

### Normalized Log / Data Source
- Source file: `./logs/live_hpa.txt`
- **Test 1:**
  - Scaled up to `5`, then `6` at near: `2026-11-13 17:42:34`, line: `57`
  - Scaled down at near: `2026-11-13 17:52:19`
- **Test 2:**
  - Scaled up to `5`, then `6` at near: `2026-11-13 18:24:11`
  - Scaled down to `5, 4, 3` at: `2026-11-13 18:31:42`

---

## 3. Rolling Updates

- **Commands:**
  ```bash
  kubectl kustomize k8s/
  kubectl apply -k k8s/
  ```
- **Rollout Timestamp:** `Fri Nov 13 06:34:40 PM UTC 2026`
- **Traffic Log Reference:** `./logs/live_traffic.txt` has log at near line: `21` (`2026-11-13T18:34:28.511+00:00`)

---

## 4. Rollout Undo

- **Command:**
  ```bash
  kubectl rollout undo deployment/devops-task \
    -n devops-task
  ```
- **Rollback Timestamp:** `Fri Nov 13 06:37:28 PM UTC 2026`
- **Traffic Log Reference:** `./logs/live_traffic.txt` log shows the output at near line: `119` (`2026-11-13T18:37:47.214+00:00`)

---

## 4. Local vs. AWS

| Area | Local (kind) | Production (EKS) |
| --- | --- | --- |
| Cluster | kind | Amazon EKS |
| Image | Local Docker image | Amazon ECR |
| External traffic | Port-forward | AWS Load Balancer Controller / ALB |
| Secrets | Kubernetes Secret | AWS Secrets Manager + CSI or External Secrets |
| Secret encryption | Local cluster defaults | AWS KMS encryption |
| Node scaling | Local node | Karpenter or Cluster Autoscaler |
| Workload identity | Local service account | EKS Pod Identity or IRSA |
| Metrics | Metrics Server | Metrics Server plus monitoring stack |
| Networking | kind networking | VPC, subnets, security groups |

### Additional Production Requirements
- Use an appropriate ingress or Gateway API implementation.
- Establish backups, disaster recovery and deployment monitoring.
- Configure centralized logging and monitoring, full observibility setup.
- Configure workload resource requests based on observed usage.
- Configure multiple availability zones.
- Use managed or appropriately configured node groups.
- Apply network policies and least-privilege IAM permissions.
- Use an external secrets-management system.

---

## Cleanup / Teardown Commands

- **Remove the application:**
  ```bash
  kubectl delete -k k8s/
  ```
- **Remove Metrics Server:**
  ```bash
  helm uninstall metrics-server -n kube-system
  ```
- **Delete the local cluster:**
  ```bash
  kind delete cluster --name devops-local
  ```

---

## Detailed Execution Logs & Walkthrough Notes

### Build the App (`1.0.0`)
```bash
docker build \
  -t devops-task:1.0.0 \
  -f apps/devops-task/Dockerfile \
  apps/devops-task

docker images devops-task
```

### 333. Load to `kind`
```bash
kind load docker-image \
  devops-task:1.0.0 \
  --name devops-local
```

**Terminal Output:**
```text
root@localhost:~/devops-asses-1# kind load docker-image \
  devops-task:1.0.0 \
  --name devops-local


Image: "devops-task:1.0.0" with ID "sha256:6a6033cbe9f22b05c750e693cd83201bc9ae066f809baa63d64a1aac27ed1dbb" not yet present on node "devops-local-control-plane", loading...
root@localhost:~/devops-asses-1# kind load docker-image   devops-task:1.0.0   --name devops-local
Image: "devops-task:1.0.0" with ID "sha256:6a6033cbe9f22b05c750e693cd83201bc9ae066f809baa63d64a1aac27ed1dbb" not yet present on node "devops-local-control-plane", loading...
root@localhost:~/devops-asses-1# 
```

- **Verify image loaded in `kind`:**
  ```bash
  docker exec devops-local-control-plane \
    crictl images | grep devops-task
  ```

### Deploy Everything & Check Initial Status
```bash
kubectl kustomize k8s/
# Then, deploy:
kubectl apply -k k8s/
```

**Terminal Output (`kubectl get all -n devops-task`):**
```text
root@localhost:~/devops-asses-1# kubectl get all -n devops-task
NAME                              READY   STATUS    RESTARTS   AGE
pod/devops-task-84cc6448b-4f829   1/1     Running   0          36s
pod/devops-task-84cc6448b-6rkc8   1/1     Running   0          37s
pod/devops-task-84cc6448b-wgcmx   1/1     Running   0          36s

NAME                  TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/devops-task   ClusterIP   10.96.137.39   <none>        80/TCP    37s

NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/devops-task   3/3     3            3           37s

NAME                                    DESIRED   CURRENT   READY   AGE
replicaset.apps/devops-task-84cc6448b   3         3         3       37s

NAME                                              REFERENCE                TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/devops-task   Deployment/devops-task   cpu: <unknown>/70%   3         6         3          37s
root@localhost:~/devops-asses-1# 
```
So, things are ready.

### Initialize 3 Replicas & Check Readiness
```bash
kubectl scale deployment devops-task \
  --replicas=3 \
  -n devops-task
```
*(Says, scaled. Check for readiness:)*

```text
root@localhost:~/devops-asses-1# kubectl rollout status deployment/devops-task \
  -n devops-task \
  --timeout=120s
deployment "devops-task" successfully rolled out
root@localhost:~/devops-asses-1# 

root@localhost:~/devops-asses-1# kubectl get all -n devops-task

kubectl get hpa -n devops-task
NAME                              READY   STATUS    RESTARTS   AGE
pod/devops-task-84cc6448b-4f829   1/1     Running   0          2m34s
pod/devops-task-84cc6448b-6rkc8   1/1     Running   0          2m35s
pod/devops-task-84cc6448b-wgcmx   1/1     Running   0          2m34s

NAME                  TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/devops-task   ClusterIP   10.96.137.39   <none>        80/TCP    2m35s

NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/devops-task   3/3     3            3           2m35s

NAME                                    DESIRED   CURRENT   READY   AGE
replicaset.apps/devops-task-84cc6448b   3         3         3       2m35s

NAME                                              REFERENCE                TARGETS       MINPODS   MAXPODS  REPLICAS   AGE
horizontalpodautoscaler.autoscaling/devops-task   Deployment/devops-task   cpu: 1%/70%   3         6  3          2m35s
NAME          REFERENCE                TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
devops-task   Deployment/devops-task   cpu: 1%/70%   3         6         3          2m36s
root@localhost:~/devops-asses-1# 
```

### Port-Forward (When Running)
```bash
kubectl port-forward \
  -n devops-task \
  service/devops-task \
  8080:80
```

### Step 14. Verify Autoscaling
- **Check current resource consumption:**
  ```bash
  kubectl top pods -n devops-task
  ```
- **Check HPA:**
  ```bash
  kubectl get hpa -n devops-task --watch
  ```
- **CPU Target Calculation:**
  - The target is `70%` CPU utilization.
  - For this application, CPU utilization is calculated against the `100m` CPU request.
  - For example:
    - `35m` CPU usage = `35%`.
    - `70m` CPU usage = `70%`.
    - `90m` CPU usage = `90%`.
  - The HPA may increase replicas when sustained utilization exceeds the target. It is not guaranteed to scale just because a request arrives; sufficient CPU load is required.

#### Testing CPU Load Notes
- Testing it: *(So, that might not be the way to test cpu load)*
- Check pods across namespaces:
  ```bash
  kubectl get pods -A
  # Example: devops-task-84cc6448b-4f829
  ```
- Generate load:
  ```bash
  kubectl exec -it -- sh -c 'yes > /dev/null &'
  ```
- Overall note: For 2 instances, with generated cpu load, this scales up and down with a time duration.

### Rolling Update Build & Load (`1.0.1`)
- **Task Requirement:** Demonstrate a zero-downtime rolling update to a new image version, and a rollback using `kubectl rollout undo`. Include the commands and output in the README.
- **Build `1.0.1`:**
  ```bash
  docker build \
    -t devops-task:1.0.1 \
    -f apps/devops-task/Dockerfile \
    apps/devops-task
  ```
- **Load to `kind`:**
  ```bash
  kind load docker-image \
    devops-task:1.0.1 \
    --name devops-local
  ```
- **Verify image loaded:**
  ```bash
  docker exec devops-local-control-plane \
    crictl images | grep devops-task
  ```
- **Port-forward / NodePort & Load Execution Note:**
  - Portforward using: Used nodeport, and forwarded with `kind-config`
  ```bash
  root@localhost:~/devops-asses-1# kubectl exec -it -n devops-task devops-task-84cc6448b-nlh9b -- sh -c 'yes'
  ```

