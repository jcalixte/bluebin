ARG GLEAM_IMAGE=ghcr.io/gleam-lang/gleam:v1.17.0-erlang-alpine

FROM ${GLEAM_IMAGE} AS build
# sqlight builds the esqlite NIF from C, so the build stage needs a toolchain.
RUN apk add --no-cache build-base sqlite-dev
WORKDIR /build
COPY . .
# The test suite is the deploy gate: a red suite fails the build before production.
ARG SKIP_TESTS=0
RUN [ "$SKIP_TESTS" = "1" ] || gleam test
RUN gleam export erlang-shipment

# Same image for the runtime: the esqlite NIF is built against this OTP and
# this libc, so running it on a different Erlang would fail to load.
FROM ${GLEAM_IMAGE}
RUN apk add --no-cache sqlite-libs
WORKDIR /app
COPY --from=build /build/build/erlang-shipment ./
RUN mkdir -p /app/data
EXPOSE 8000
ENV PORT=8000
ENTRYPOINT ["./entrypoint.sh", "run"]
