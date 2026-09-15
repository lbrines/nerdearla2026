ARG GO_VERSION
FROM golang:${GO_VERSION}-alpine AS build

WORKDIR /src
COPY go.mod go.sum ./
COPY scenario/services/logging/logger.go ./scenario/services/logging/
COPY scenario/services/gateway/main.go scenario/services/gateway/metrics.go ./scenario/services/gateway/
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /gateway ./scenario/services/gateway

FROM scratch
COPY --from=build /gateway /gateway
ENTRYPOINT ["/gateway"]
