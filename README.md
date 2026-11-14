# DevOps Engineer Technical Assessment — `<APP_NAME>`

An end-to-end containerized web service built, tested, scanned, provisioned on AWS via Terraform, deployed to EC2 and Kubernetes, and monitored with a full Prometheus, Loki, Grafana Alloy, Node Exporter, and cAdvisor observability stack.

---

## Table of Contents

// TODO: generate it

---

## 1. Project Structure & Prerequisites

### 1.1 Project Structure

```text
├── .github/
│   └── workflows/                 # CI (PR lint/test/scan) & CD (ECR push + EC2 deploy)
├── apps/
│   └── devops-task/               # Web service source code, unit tests & multi-stage Dockerfile
├── docker-compose.yml             # Local app runtime (port 8080, healthcheck, resource limits)
├── docker-compose.monitoring.yml  # Local observability stack (Prometheus, Grafana, Loki, Alloy, Node Exporter, cAdvisor, Alert-manager)
├── k8s/                           # Kubernetes manifests & Kustomize overlays
├── monitoring/                    # Prometheus, Loki, Grafana Alloy & Grafana provisioned dashboards/datasources
├── reports/                       # Execution logs, test/plan outputs & screenshots for each step
├── scripts/
│   ├── dev_k8s/                   # Local kind cluster bootstrap & Kubernetes test scripts
│   └── system_health_check/       # Linux server health check script (system_health.sh) & timer unit
└── terraform/                     # AWS VPC/EC2/ECR/IAM/CloudWatch IaC with S3 remote state
```

### 1.2 Prerequisites

Install the following tools before running the application, infrastructure, or test scripts:

* **Required:** `docker` (with Docker Compose v2), `awscli`, `terraform`, `kind`, `kubectl`, `shellcheck`
* **Optional:** `gh` (GitHub CLI), `gh nektos plugin`, `hadolint` (Docker lint)

> **Environment Note:** All scripts, Docker Compose stacks, and deployment workflows were developed and verified on **Ubuntu 24.04 LTS** on a remote Linux server. Docker networking, cAdvisor/Node Exporter `/proc` and `/sys` mounts, and file permissions may behave differently on **macOS** or **Windows**.

### 1.3 Application Endpoints & Image Footprint

Go application. 

Entrypoint & Port: server listening on 8080/tcp

* **Endpoints:**
  * `GET /` — Returns `{"message": "Hello from DevOps Task!", "status": "running", "version": "<APP_VERSION>"}`
  * `GET /health` — Liveness and readiness health probe
  * `GET /metrics` — Prometheus-format metrics (request counter, error counter, request duration histogram)
* **Container Image:** Running as a non-root user (`appuser:appgroup`).
* **Final Image Size:** **`Disk usage: 28.7 MB, Acutal Image size / Content size: 7.92 MB`** (verified via `docker images` and `docker image inspect devops-task:1.0.` ).

golang:1.27.3-alpine as builder,
and alpine:3.21
with multi-stage, cross compilation for x86 and arm64. 

### 1.4 ENV Setup and Running the App & Observability Stack

#### Environment Variables

* **Application environment variables** (configured inside `docker-compose.yml`):
  ```env
  PORT=
  LOG_LEVEL=
  ENV_NAME=
  APP_VERSION=
  ```

* **Observability environment variables** (loaded from `.env` file):
  ```env
  GF_SECURITY_ADMIN_USER=
  GF_SECURITY_ADMIN_PASSWORD=
  DISCORD_WEBHOOK_URL=
  ```

#### Running Locally

* **Running the app only** (runs on port `8080`):
  ```bash
  docker compose up
  ```

* **Running the app along with the observability stack**:
  ```bash
  docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up
  ```

With the current configuration:
* **Application** runs on **`http://localhost:8080`**
* **Grafana** runs on **`http://localhost:3090`** (datasources and dashboards are provisioned automatically from `./monitoring/`)

 
## 2. Tests, health script, Terraform code, Kubernetes

### 2.1
for testing go app
cd apps/devops-task
and run go test -v -race -count 10 ./...

### 2.2
Run checks, lints, tests using gh action locally using nektos (also install )
gh act -W .github/workflows/1-pr.yml 

### 2.3 health script


exact steps and screenshots can be at reports/5-LINUX-SCRIPTING.md

### 2.3 Terraform, aws deployment

Ensure aws is configued and logged in. 

exact steps and screenshots can be at reports/2-DEPLOYMENT_TERRAFORM.md

### 2.4 Kubernetes

exact steps and screenshots can be at reports/3-DEPLOYMENT-k8s.md


### 2.5 Obsersvability, Alerts, Monitoring

exact steps and screenshots can be at reports/4-OBSERVABILITY.md













## 3. Architecture Overview

An architecture diagram covering Code Commit → CI (lint, test, scan) → Registry → Deployment
to EC2, along with the Kubernetes deployment flow and the observability stack (how metrics
and logs flow from the app and host into Grafana).


### 3.1 Architecture Diagram for Code to EC2

```mermaid
flowchart TD
    %% Styling
    classDef git fill:#1f2937,stroke:#60a5fa,stroke-width:2px,color:#f9fafb
    classDef ci fill:#1e3a8a,stroke:#93c5fd,stroke-width:2px,color:#eff6ff
    classDef aws fill:#78350f,stroke:#fbbf24,stroke-width:2px,color:#fef3c7
    classDef ec2 fill:#064e3b,stroke:#34d399,stroke-width:2px,color:#ecfdf5
    classDef fail fill:#7f1d1d,stroke:#f87171,stroke-width:2px,color:#fef2f2
    classDef gate fill:#374151,stroke:#d1d5db,stroke-width:2px,color:#ffffff

    subgraph S1["1. Code Commit & Trigger Events"]
        DEV["Developer Commits Code<br/>(apps/devops-task)"]:::git
        DEV --> PR["Open / Update Pull Request<br/>(Target: main)"]:::git
        DEV -. "Direct Push<br/>(e.g., Rollback Test)" .-> MAIN["Push Event on main"]:::git
    end

    subgraph S2["2. CI Gate (Workflow: PR Checks)"]
        PR --> C1["Code Lint & Test<br/>(Go 1.27.x, GolangCI-Lint v2.15.0,<br/>go test + coverage)"]:::ci
        PR --> C2["Docker & Shell Linting<br/>(Hadolint ignore DL3018 +<br/>ShellCheck on ./)"]:::ci
        PR --> C3["Build & Security Scan<br/>(Local Docker Build + Trivy<br/>CRITICAL OS/Lib Scan)"]:::ci
        C1 & C2 & C3 --> G1{"All PR Checks<br/>Passed?"}:::gate
        G1 -- "No" --> F1["Block PR Merge<br/>(Fix & Re-push)"]:::fail
        G1 -- "Yes" --> MERGE["Merge PR into main"]:::git
        MERGE --> MAIN
    end

    subgraph S3["3. Release & Multi-Arch Build (Workflow: Deploy to EC2)"]
        MAIN --> V["Compute Semantic Version<br/>(Concurrency: release-version | Reuse HEAD tag<br/>or bump [major]/[minor]/patch -> vX.Y.Z)"]:::ci
        V --> OIDC["Authenticate via GitHub OIDC<br/>(sts:AssumeRoleWithWebIdentity -> GitHubActionsRole)"]:::aws
        OIDC --> BX["Docker Buildx Multi-Arch Build<br/>(QEMU + linux/amd64, linux/arm64 + GHA Cache)"]:::ci
    end

    subgraph S4["4. Immutable Container Registry (Amazon ECR)"]
        BX --> ECR["Push to Amazon ECR (devops-task)<br/>Immutable Tags: sha-{full-sha} & vX.Y.Z<br/>+ ECR scanOnPush"]:::aws
    end

    subgraph S5["5. Zero-SSH Deployment to EC2 & Automated Rollback"]
        ECR --> SSM["AWS SSM Send-Command<br/>(Concurrency: deploy-ec2 | 300s Timeout,<br/>Polled Every 5s)"]:::aws
        SSM --> HOST["EC2 Host (Amazon Linux 2023)<br/>Run /usr/local/bin/deploy-app.sh"]:::ec2
        HOST --> PULL["Pull sha-{full-sha} from ECR &<br/>Swap Container on Port 8080"]:::ec2
        PULL --> SMOKE{"Host Smoke Test<br/>GET /health == 200?"}:::gate
        SMOKE -- "Yes (Healthy)" --> LIVE["Deployment Success<br/>Live on vX.Y.Z (:8080)<br/>Host Logs -> CloudWatch"]:::ec2
        SMOKE -- "No (Unhealthy / 500)" --> RB["Automatic Host Rollback<br/>Revert to Previous Healthy Image<br/>& Exit 1 (Workflow Marked Failed)"]:::fail
    end
```

### 3.2 Architecture Diagram for k8s

```mermaid

flowchart TD
    classDef infra fill:#e1f5fe,stroke:#0288d1,stroke-width:2px,color:#01579b
    classDef kustomize fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px,color:#4a148c
    classDef k8s fill:#e8f5e9,stroke:#388e3c,stroke-width:2px,color:#1b5e20
    classDef pod fill:#fff3e0,stroke:#f57c00,stroke-width:2px,color:#e65100
    classDef traffic fill:#fce4ec,stroke:#c2185b,stroke-width:2px,color:#880e4f

    subgraph Infra ["1. Local Cluster & Prerequisites"]
        Kind["kind-config.yaml<br/>Cluster: devops-local (v1.37.0)<br/>Host:30080 -> Node:30080"]:::infra
        ImgLoad["Local Image Load<br/>kind load docker-image devops-task:1.0.1"]:::infra
        Metrics["Helm: metrics-server<br/>(--kubelet-insecure-tls)"]:::infra
    end

    subgraph Build ["2. Kustomize Build (kubectl apply -k k8s/)"]
        Kust["kustomization.yaml<br/>Target Namespace: devops-task"]:::kustomize
        CMGen["configMapGenerator<br/>devops-task-config-&lt;hash&gt;<br/>(PORT=8080, APP_VERSION=1.0.1)"]:::kustomize
        SecGen["secretGenerator<br/>devops-task-secret-&lt;hash&gt;<br/>(from secrets/app.env)"]:::kustomize
        ImgPatch["Image Transformer<br/>devops-task:1.0.0 -> 1.0.1"]:::kustomize

        Kust --> CMGen
        Kust --> SecGen
        Kust --> ImgPatch
    end

    subgraph Cluster ["3. Kubernetes Control Plane (ns: devops-task)"]
        NS["Namespace: devops-task"]:::k8s
        Svc["Service: devops-task (NodePort)<br/>NodePort 30080 -> Port 80 -> Target 8080"]:::k8s
        Deploy["Deployment: devops-task<br/>Default Replicas: 1<br/>RollingUpdate (maxSurge: 1, maxUnavailable: 0)"]:::k8s
        HPA["HPA: devops-task (autoscaling/v2)<br/>Min: 3 | Max: 6 | Target CPU: 70%<br/>Up: +2/60s (0s win) | Down: -1/60s (300s win)"]:::k8s
        SecretObj["Secret: devops-task-secret-&lt;hash&gt;<br/>(Created in etcd, currently unreferenced)"]:::k8s

        Kust --> NS
        Kust --> Svc
        CMGen --> Deploy
        ImgPatch --> Deploy
        SecGen --> SecretObj
        Kust --> HPA

        Metrics -.->|Scrapes Pod CPU| HPA
        HPA <-->|Scales 1 -> 3..6 Replicas| Deploy
    end

    subgraph Runtime ["4. Pod Runtime & Health (Node: devops-local)"]
        Pod["Pod: devops-task:1.0.1 (IfNotPresent)<br/>UID/GID: 10001 | ReadOnlyFS | Drop ALL<br/>No SA Token | Req: 100m/32Mi | Lim: 500m/128Mi"]:::pod
        Probes["Kubelet HTTP Probes: GET /health:8080<br/>Readiness: delay 3s, period 5s<br/>Liveness: delay 5s, period 10s"]:::pod

        ImgLoad -.->|Provides local image| Pod
        Deploy -->|Manages| Pod
        Probes -->|Gates Endpoints / Restarts| Pod
    end

    User(("External Client<br/>localhost:30080")):::traffic
    User -->|TCP 30080| Kind
    Kind -->|NodePort 30080| Svc
    Svc -->|Routes to Ready Pods :8080| Pod

```

### 3.3 Architecture Diagram for Observablity stack

```mermaid
flowchart LR
    subgraph Sources["Telemetry Sources (Host & Containers)"]
        APP["app (:8080)<br/>HTTP Metrics & JSON stdout/stderr"]
        HOST["Host OS (/, /proc, /sys)<br/>& /dev/kmsg"]
        SOCK["/var/run/docker.sock<br/>Container stdout/stderr"]
    end

    subgraph Collectors["Exporters & Log Agent"]
        NE["node-exporter (:9100)<br/>Host Metrics"]
        CAD["cadvisor (:8080)<br/>Container cgroup Metrics"]
        ALLOY["Grafana Alloy (:12345)<br/>JSON Parse + Label/Metadata Split"]
    end

    subgraph Storage["Storage & Alert Engine"]
        PROM["Prometheus (:9090)<br/>Scrape: 15s | Retention: 15d / 2GB"]
        LOKI["Loki (:3100)<br/>TSDB v13 | Retention: 7d (168h)"]
        AM["Alertmanager (:9093)<br/>Group Wait: 15s"]
    end

    subgraph Consumers["Visualization & Notifications"]
        GRAF["Grafana (:3090 -> :3000)<br/>App, Containers & Host Dashboards"]
        DISC["Discord Webhook<br/>[FIRING] & [RESOLVED] Alerts"]
    end

    %% Metrics Pull Flow
    HOST -->|ro mount| NE
    HOST -->|ro mounts + privileged| CAD
    PROM -->|Scrape 15s| APP
    PROM -->|Scrape 15s| NE
    PROM -->|Scrape 15s| CAD

    %% Logs Push Flow
    APP -.->|stdout/stderr| SOCK
    SOCK -->|ro mount| ALLOY
    ALLOY -->|HTTP Push /loki/api/v1/push| LOKI

    %% Alerting Flow
    PROM -->|Eval rules 15s| AM
    AM -->|webhook_url_file| DISC

    %% Grafana Query Flow
    GRAF -->|PromQL| PROM
    GRAF -->|LogQL| LOKI
```







## 4. Design Decisions
 section explaining key trade-offs (e.g. distroless vs Alpine, EC2 vs ECS vs
EKS, your tagging and secrets strategy, log label choices).


# 8. A What I would improve with more time

With more time, 
i would improve it by going through a checklist of testing and chaos engineering to 
push it's limit, calculate ~exact numbers of rps, limits, errors spikes and thorttling it on different percentile to get more detailed scenaiors how it will work under pressure and high load. 
Load balancing for different layers and similar...


1. Better documentation
2. Loading all envs from .env file instead of mixed env file and docker-compose.yml's env




# 9. A short note on whether and how you used AI tools during this task. Using them is allowed; we
only ask that you can explain every part of your submission.

Most of the code parts are generated using with deliberate instructions with task context. And, each part is hand checked, and reports generated are inside ./reports/ with codes for steps producing each. 
