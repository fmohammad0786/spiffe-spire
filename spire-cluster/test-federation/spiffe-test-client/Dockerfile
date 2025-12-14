FROM golang:1.25.3-alpine AS builder
WORKDIR /app
COPY main.go go.mod go.sum ./
RUN CGO_ENABLED=0 go build -o client main.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates curl
WORKDIR /root/
COPY --from=builder /app/client .
CMD ["./client"]
