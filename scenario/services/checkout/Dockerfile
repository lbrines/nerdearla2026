ARG GO_VERSION
FROM golang:${GO_VERSION}-alpine AS build

WORKDIR /src
COPY go.mod ./
COPY scenario/services/checkout/main.go ./scenario/services/checkout/main.go
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /checkout ./scenario/services/checkout

FROM scratch
COPY --from=build /checkout /checkout
ENTRYPOINT ["/checkout"]
