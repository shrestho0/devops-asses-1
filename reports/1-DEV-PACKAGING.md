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

- **Final Image Size:** **~28 MB** 
  *(~8.46 MB for the Alpine base layer + ~9.49 MB for the statically linked, stripped Go binary)*
- **Base Image:** `alpine:3.21` (Pinned strictly via versioning)
- **Security:** 
  - Runs as an unprivileged, non-root user (`appuser`).
  - Binary is statically linked (`CGO_ENABLED=0`) shrinking the attack surface.
- **Resilience:** Includes a native Docker `HEALTHCHECK` probing the `/health` endpoint every 30 seconds.

Output of `docker history  devops-asses-1-app:latest` : 
Alpine base layer: 8.46 MB

Go binary: 9.49 MB

Timezone data: 1.57 MB

Dependencies: 1.22 MB

User/group setup: 41 kB

root@localhost:~/devops-asses-1# docker image inspect devops-asses-1-app:latest   --format='{{.Size}}' | numfmt --to=iec
28M


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

Remove the container: docker rm -f devops-task-app