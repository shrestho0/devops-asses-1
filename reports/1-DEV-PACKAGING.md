
## 1-DEV-PACKAGING

### Application Directory

```bash
cd apps/devops-task
```

### Entry Point

```text
apps/cmd/api/main.go
```

### Run Application

```bash
PORT="9090" ENV_NAME="production" LOG_LEVEL="debug" APP_VERSION="2.0.0" go run cmd/api/main.go
```

### Testing

**General — All Test Cases**

```bash
go test -v ./...
```

**Race Condition Check**

```bash
go test -v -race ./...
```

**Repeated Flaky Test Check**

```bash
go test -v -race -count 10 ./...
```

---

## 2. Docker Image Specifications

This project utilizes a multi-stage Dockerfile to ensure strict security and minimal resource footprint.

### Docker Image Layer Breakdown

Output of:

```bash
docker history devops-asses-1-app:latest
```

| Layer | Size |
|---|---:|
| Alpine base layer | 8.46 MB |
| Go binary | 9.49 MB |
| Timezone data | 1.57 MB |
| Dependencies | 1.22 MB |
| User/group setup | 41 kB |

### Total Image Size

```bash
root@localhost:~/devops-asses-1# docker image inspect devops-asses-1-app:latest --format='{{.Size}}' | numfmt --to=iec
```

**Image size:** 28M

---

## 3. Docker Build and Run

### Build the Image

```bash
docker build -t devops-task:v1 .
```

### Run the Container

```bash
docker run -d \
  --name devops-task-app \
  -p 8080:8080 \
  -e PORT=8080 \
  -e LOG_LEVEL=info \
  -e ENV_NAME=production \
  devops-task:v1
```

### Remove the Container

```bash
docker rm -f devops-task-app
```