# Bluebin

[bluebin.app](https://bluebin.app)

A pull system for software teams, built on Toyota Production System principles: Takt Time, one-piece flow, Heijunka and Just-In-Time.

## Develop

```bash
pnpm install
pnpm dev           # SPA on :5173, /api proxied to :8000
pnpm lint          # oxlint  (pnpm lint:fix to autofix)
pnpm fmt           # oxfmt   (pnpm fmt:check to verify only)
pnpm build         # vue-tsc + vite build, the same build Coolify runs

cd backend && gleam run     # API on :8000 (needs Erlang/OTP and a C toolchain)
docker compose up           # SPA + API together, as deployed
```

## Deploy

Pushes to `main` are picked up by Coolify at https://platform.apoena.dev and land on https://bluebin.app.

<!-- docs:start -->

## Documentation

- [CONTEXT.md](./CONTEXT.md) — the ubiquitous language: every domain term and its relationships
- [DESIGN.md](./DESIGN.md) — the QFD design: goals, functions, components and trade-offs
- [ADR-0001](./docs/adr/0001-pieces-never-move-backward.md) — a Piece never moves backward; Rework happens where the defect is found
- [ADR-0002](./docs/adr/0002-flow-event-log-with-current-state.md) — flow event log and current state, written in one transaction

<!-- docs:end -->
