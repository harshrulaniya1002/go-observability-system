# Build stage
FROM golang:1.25-alpine AS builder

WORKDIR /build

# Copy go mod files and download dependencies
COPY go.mod go.sum ./
RUN go mod download && go mod verify

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o app .

# Runtime stage
FROM alpine:latest

# Install required packages
RUN apk --no-cache add ca-certificates curl

WORKDIR /root/

# Copy the built application
COPY --from=builder /build/app .

EXPOSE 8080

# Health check
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

CMD ["./app"]
