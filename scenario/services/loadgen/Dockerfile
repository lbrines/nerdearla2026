ARG GO_VERSION
FROM golang:${GO_VERSION}-alpine AS build

WORKDIR /src
COPY go.mod ./
COPY scenario/services/loadgen/main.go ./scenario/services/loadgen/main.go
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /loadgen ./scenario/services/loadgen

FROM scratch
COPY --from=build /loadgen /loadgen
ENTRYPOINT ["/loadgen"]
