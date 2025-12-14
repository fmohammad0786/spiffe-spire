FROM golang:1.25.3-alpine AS builder
WORKDIR /app
COPY main.go .
RUN go mod init testapp \
    && go get github.com/spiffe/go-spiffe/v2@v2.6.0 \
    && go mod tidy \
    && CGO_ENABLED=0 go build -o server main.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates curl
WORKDIR /root/
COPY --from=builder /app/server .
EXPOSE 8443
CMD ["./server"]
