FROM golang:1.22-alpine AS builder

WORKDIR /app
COPY . .
RUN go build -o auth-service

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/auth-service .

USER nobody

EXPOSE 4000
CMD ["./auth-service"]