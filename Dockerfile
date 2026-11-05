# One image, so Coolify can do a rolling update: it starts the new container,
# waits for its healthcheck, moves the traffic, then stops the old one. Its
# Docker Compose build pack cannot, and stops the stack before starting again.

FROM node:22-alpine AS web
WORKDIR /app
COPY package.json pnpm-lock.yaml* ./
RUN corepack enable && pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

ARG GLEAM_IMAGE=ghcr.io/gleam-lang/gleam:v1.17.0-erlang-alpine

FROM ${GLEAM_IMAGE} AS api
# sqlight builds the esqlite NIF from C, so the build stage needs a toolchain.
RUN apk add --no-cache build-base sqlite-dev
# Link the NIF to Alpine's libsqlite3 instead of compiling the bundled
# sqlite3.c amalgamation, which costs about a minute per build mode.
ENV ESQLITE_USE_SYSTEM=1
WORKDIR /build
COPY backend/ .
# The test suite is the deploy gate: a red suite fails the build before production.
ARG SKIP_TESTS=0
RUN [ "$SKIP_TESTS" = "1" ] || gleam test
RUN gleam export erlang-shipment

# Same image for the runtime: the esqlite NIF is built against this OTP, this
# libc and this libsqlite3, so running it on a different base would fail to load.
FROM ${GLEAM_IMAGE}
RUN apk add --no-cache sqlite-libs
WORKDIR /app
COPY --from=api /build/build/erlang-shipment ./
COPY --from=web /app/dist ./static
# The SQLite file lives here: Coolify mounts the persistent volume on it.
RUN mkdir -p /app/data
EXPOSE 8000
ENV PORT=8000
# Coolify reads this and moves the traffic only once it passes.
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8000/api/health || exit 1
ENTRYPOINT ["./entrypoint.sh", "run"]
