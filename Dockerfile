# ---------------------------------------------
# 1. Builder Stage
# ---------------------------------------------
FROM golang:1.23-alpine AS builder

# Install git (required for Go modules)
RUN apk add --no-cache git

WORKDIR /app

# Go dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy source
COPY . .

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -o server ./cmd/server

# ---------------------------------------------
# 2. Runtime Stage (Distroless)
# ---------------------------------------------
FROM gcr.io/distroless/static

COPY --from=builder /app/server /server

USER 65532:65532

EXPOSE 8080

ENTRYPOINT ["/server"]
