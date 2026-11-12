# devops-asses-1


## Development
### App Dir:

cd apps/devops-task

### Entry point: 

apps/cmd/api/main.go 

### Run 

PORT="9090" ENV_NAME="production" LOG_LEVEL="debug" APP_VERSION="2.0.0" go run cmd/api/main.go

### Test (General, all cases)

go test -v ./...

Testing with race condition check
go test -v -race ./...

Repeated flaky test 
go test -v -race -count 10 ./...


## Docker Image Specifications

This project utilizes a multi-stage Dockerfile to ensure strict security and minimal resource footprint. 

- **Final Image Size:** **~XXX MB** 
  *(~7.5 MB for the Alpine base layer + ~10 MB for the statically linked, stripped Go binary)*
- **Base Image:** `alpine:3.20.2` (Pinned strictly via SHA256 digest)
- **Security:** 
  - Runs as an unprivileged, non-root user (`appuser`).
  - Binary is statically linked (`CGO_ENABLED=0`) shrinking the attack surface.
- **Resilience:** Includes a native Docker `HEALTHCHECK` probing the `/health` endpoint every 30 seconds.


### Build and Run

```bash
# Build the image
docker build -t devops-task:v1 .

# Run the container (passing environment variables)
docker run -d \
  --name devops-task-app \
  -p 8080:8080 \
  -e PORT=8080 \
  -e LOG_LEVEL=info \
  -e ENV_NAME=production \
  devops-task:v1