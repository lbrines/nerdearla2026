ARG GO_VERSION
FROM golang:${GO_VERSION}-alpine AS build

WORKDIR /src
COPY go.mod ./
COPY scenario/services/gateway/main.go ./scenario/services/gateway/main.go
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /gateway ./scenario/services/gateway

FROM scratch
COPY --from=build /gateway /gateway
ENTRYPOINT ["/gateway"]
