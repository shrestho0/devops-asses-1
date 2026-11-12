# ==============================================================================
# Stage 1: Builder
# Using specific Alpine-based Go image via version tag
# ==============================================================================
FROM golang:1.27.3-alpine AS builder

# Expose automatic multi-platform build arguments from Docker Buildx
ARG TARGETOS
ARG TARGETARCH

# Set the working directory outside $GOPATH to enable module support
WORKDIR /app

# Install git (required for fetching some Go dependencies) and tzdata
RUN apk add --no-cache git tzdata

# Copy go.mod and go.sum first to leverage Docker layer caching
COPY go.mod go.sum ./
RUN go mod download

# Copy the rest of the source code
COPY . .

# Build a statically linked Go binary
# -w and -s strip debugging information to reduce binary size
# CGO_ENABLED=0 ensures the binary is statically linked and doesn't rely on host C libraries
# RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o /app/server ./cmd/api

# Use the dynamic arguments instead of hardcoding GOOS=linux GOARCH=amd64
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64} go build -ldflags="-w -s" -o /app/server ./cmd/api

# ==============================================================================
# Stage 2: Final minimal image
# ==============================================================================
FROM alpine:3.21

# OCI standard labels
LABEL org.opencontainers.image.title="DevOps Task Web Service" \
    org.opencontainers.image.description="A small Go web service with Prometheus metrics" \
    org.opencontainers.image.version="1.0.0" \
    org.opencontainers.image.authors="Sadril Amin Shrestho" \
    org.opencontainers.image.source="https://github.com/shrestho0/devops-asses-1" \
    org.opencontainers.image.vendor="TestVendor"

# Create a non-root user and group
# Alpine's addgroup/adduser handles creating unique UIDs/GIDs
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Install CA certificates (for outbound HTTPS calls if needed) and retain minimal tools for HEALTHCHECK
RUN apk add --no-cache ca-certificates

# Copy timezone data from the builder
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# Copy the compiled binary from the builder stage
COPY --from=builder --chown=appuser:appgroup /app/server /usr/local/bin/server

# Switch to the non-root user
USER appuser:appgroup

# Expose the application port
EXPOSE 8080

# Configure healthcheck using Alpine's built-in wget
# Docker will run this periodically to assess container health
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -q -O- http://localhost:8080/health || exit 1

# Execute the binary
ENTRYPOINT ["server"]