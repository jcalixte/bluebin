#!/usr/bin/env sh
# Run the Gleam test suite.
#
#   ./test.sh            native when Erlang/OTP and a C toolchain are present,
#                        otherwise inside the same image the deploy builds from
#   ./test.sh --docker   force the container route
#
# sqlight compiles the esqlite NIF from C, so a native run needs gcc and make
# on top of gleam and erlang.
set -eu

IMAGE="ghcr.io/gleam-lang/gleam:v1.17.0-erlang-alpine"
cd "$(dirname "$0")"

native_possible() {
  [ "${1:-}" != "--docker" ] &&
    command -v gleam >/dev/null 2>&1 &&
    command -v escript >/dev/null 2>&1 &&
    command -v cc >/dev/null 2>&1
}

if native_possible "${1:-}"; then
  exec gleam test
fi

if ! docker info >/dev/null 2>&1; then
  echo "No Erlang/OTP here and no Docker daemon either." >&2
  echo "Install Erlang + gcc, start Docker, or run scripts/test-api.sh against a deploy." >&2
  exit 1
fi

exec docker run --rm -v "$PWD:/build" -w /build "$IMAGE" \
  sh -c 'apk add --no-cache build-base sqlite-dev >/dev/null && gleam test'
