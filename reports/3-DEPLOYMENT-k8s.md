
0. (Though the task asked at least 2 replicas, i mis-read/mis-understood and kept min replica to 3 and scaled upto 6. Currently, ignoring this part due to shortage of time, but, the same thing is reproducble in the very same way )

// TODO: OPS NOTE :: revisit, redo these steps to ensure we start with 2 replicas

1.  Setup ... ... ...

Control plane setup
with port binding host to container port 30080

create the cluster 
kind create cluster \
  --config k8s/1-kind-config.yml \
  --wait 120s

verify

kubectl cluster-info --context kind-devops-local
kubectl get nodes

setting up the metrics server

helm repo add metrics-server \
  https://kubernetes-sigs.github.io/metrics-server/

helm repo update


helm upgrade --install metrics-server \
  metrics-server/metrics-server \
  --version 3.14.0 \
  --namespace kube-system \
  --values k8s/helm/metrics-server-values.yml \
  --wait


Build the docker image and verify
docker build \
  -t devops-task:1.0.0 \
  -f apps/devops-task/Dockerfile \
  apps/devops-task


docker images devops-task

Load image to kind

kind load docker-image \
  devops-task:1.0.0 \
  --name devops-local

Verify if the image loaded
docker exec devops-local-control-plane \
  crictl images | grep devops-task


Initial deployment,
build manifests with kubectl kustomize k8s/
rollout deployment kubectl apply -k k8s/



2. Checking HPA, with generating load on cpu. 

kubectl exec -it -n devops-task devops-task-84cc6448b-nlh9b -- sh -c 'yes'
and
wrk -t16 -c200 -d2400s --latency http://127.0.0.1:30080/

Show normalized log/data from:
./logs/live_hpa.txt

test 1:
scaled up to 5, then 6,
at near: 2026-11-13 17:42:34, line: 57. 

and, scaled down
at near: 2026-11-13 17:52:19

test 2:
scaled up to 5, then, 6
at near: 2026-11-13 18:24:11
scaled down to 5,4,3 
2026-11-13 18:31:42



3. Rolling updates

command: 
kubectl kustomize k8s/
kubectl apply -k k8s/

Rollout at
Fri Nov 13 06:34:40 PM UTC 2026
./logs/live_traffic.txt has log at near line: 21 (2026-11-13T18:34:28.511+00:00)

4. Rollout undo at,

kubectl rollout undo deployment/devops-task \
  -n devops-task

  Fri Nov 13 06:37:28 PM UTC 2026

./logs/live_traffic.txt log shows the output at near line: 119 (2026-11-13T18:37:47.214+00:00)




## Architecture


```mermaid

flowchart TB
    USER(["External User"])
    HOST["Local Machine<br/>localhost:30080"]

    subgraph KIND["Kind Cluster: devops-local"]
        NODE["Control Plane Node<br/>kindest/node:v1.37.0"]
        PORT["Port Mapping<br/>30080 → 30080"]

        subgraph NS["Namespace: devops-task"]
            SVC["NodePort Service<br/>devops-task<br/>80 → 8080<br/>NodePort: 30080"]

            subgraph APP["Deployment: devops-task"]
                HPA["Horizontal Pod Autoscaler<br/>CPU Target: 70%<br/>Min: 3 | Max: 6"]

                subgraph PODS["Application Pods: 3–6 Replicas"]
                    P1["Pod 1"]
                    P2["Pod 2"]
                    P3["Pod 3"]
                    PN["Pod N"]
                end

                IMAGE["Container Image<br/>devops-task:1.0.1<br/>Port: 8080"]
            end

            CM["ConfigMap<br/>PORT=8080<br/>LOG_LEVEL=debug<br/>ENV_NAME=local_k8s<br/>APP_VERSION=1.0.1"]

            SEC["Secret<br/>devops-task-secret<br/>Generated from app.env"]

            HEALTH["Health Checks<br/>Readiness: /health<br/>Liveness: /health"]
        end
    end

    subgraph KUSTOMIZE["Kustomize: ./k8s"]
        K["kustomization.yaml"]
        RES["Resources<br/>namespace.yaml<br/>deployment.yaml<br/>service.yaml<br/>hpa.yaml"]
        GEN["ConfigMap Generator<br/>Secret Generator"]
        IMG["Image Transformation<br/>Tag: 1.0.1"]
        APPLY["kubectl apply -k ./k8s"]
    end

    USER --> HOST
    HOST --> PORT
    PORT --> NODE
    NODE --> SVC

    SVC --> P1
    SVC --> P2
    SVC --> P3
    SVC --> PN

    IMAGE --> PODS
    CM -.->|"envFrom"| PODS
    SEC -.->|"Optional secretKeyRef"| PODS
    HEALTH -.->|"Probes"| PODS

    HPA -.->|"Monitors CPU"| PODS
    HPA -.->|"Scales 3–6 replicas"| APP

    K --> RES
    K --> GEN
    K --> IMG
    RES --> APPLY
    GEN --> APPLY
    IMG --> APPLY
    APPLY --> NODE

    classDef user fill:#dbeafe,stroke:#2563eb,color:#1e3a8a
    classDef infra fill:#e0f2fe,stroke:#0284c7,color:#075985
    classDef app fill:#dcfce7,stroke:#16a34a,color:#14532d
    classDef config fill:#fef3c7,stroke:#d97706,color:#78350f
    classDef scaling fill:#f3e8ff,stroke:#9333ea,color:#581c87
    classDef deploy fill:#fce7f3,stroke:#db2777,color:#831843

    class USER,HOST user
    class NODE,PORT,SVC infra
    class P1,P2,P3,PN,IMAGE,HEALTH app
    class CM,SEC config
    class HPA scaling
    class K,RES,GEN,IMG,APPLY deploy

```