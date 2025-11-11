FROM golang:1.23-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o auth-service

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/auth-service .

USER nobody

EXPOSE 4000
CMD ["./auth-service"]