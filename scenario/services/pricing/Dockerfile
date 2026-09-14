ARG GO_VERSION
FROM golang:${GO_VERSION}-alpine AS build

WORKDIR /src
COPY go.mod ./
COPY scenario/services/pricing/main.go ./scenario/services/pricing/main.go
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /pricing ./scenario/services/pricing

FROM scratch
COPY --from=build /pricing /pricing
ENTRYPOINT ["/pricing"]
