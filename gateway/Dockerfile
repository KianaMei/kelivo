FROM golang:1.22-alpine AS build

WORKDIR /src
RUN apk add --no-cache ca-certificates

COPY go.mod ./
COPY . ./

ENV CGO_ENABLED=0
RUN go build -trimpath -ldflags="-s -w" -o /out/kelivo-gateway ./...

FROM alpine:3.20
RUN apk add --no-cache ca-certificates && adduser -D -H -u 10001 app && mkdir -p /data/uploads && chown -R app:app /data
USER app
WORKDIR /app

COPY --from=build /out/kelivo-gateway /app/kelivo-gateway

ENV LISTEN_ADDR=:8080
EXPOSE 8080
ENTRYPOINT ["/app/kelivo-gateway"]
