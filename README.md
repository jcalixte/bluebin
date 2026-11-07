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
docker build -t bluebin . && docker run -p 8000:8000 bluebin
                            # SPA + API in one image, as deployed, on :8000
```

## Test the API

```bash
backend/test.sh             # Gleam suite: Takt arithmetic, schema, seed, pull rules
                            # runs natively with Erlang + gcc, else in the deploy image
scripts/test-api.sh         # smoke-test a deploy: scripts/test-api.sh http://localhost:8000
```

The `Dockerfile` runs `gleam test` during the build, so a red suite fails the
deploy before it reaches production.

## Deploy

Pushes to `main` are picked up by Coolify at https://platform.apoena.dev and land on https://bluebin.app.

One image: the Gleam API serves the built SPA from `static/`. Coolify builds it
with the Dockerfile build pack and does a rolling update: the new container
starts, passes `/api/health`, takes the traffic, then the old one stops. For a
few seconds both write to the SQLite file, so a migration must stay additive:
the old code must still run on the new schema. The schema lives in one place,
`schema` in `backend/src/bluebin/db.gleam`, at `schema_version`; a database
file at any other version is refused, never read.

### Sign-in and Workspaces

Traefik forward auth sends each request to authentik (`auth.apoena.dev`,
provider and app `bluebin`) and copies the `X-authentik-uid` header from its
answer, which replaces any value the client sends. The API trusts only that
header: each uid is one Workspace. A request without it uses the shared
`public` Workspace; a uid that is not a safe file name gets `401`. In dev, the
Vite proxy sends `X-authentik-uid: dev`.

A Workspace holds as many named Lines as its owner makes, one SQLite
file each, so no query can read across two of them:

| Line                                                 | File                                | API                               |
| ---------------------------------------------------- | ----------------------------------- | --------------------------------- |
| `main`, made on the first request with the demo data | `data/workspaces/<uid>.db`          | `/api/lines/main/…`, and `/api/…` |
| each one made with **New Line…**, empty              | `data/workspaces/<uid>/ln-<hex>.db` | `/api/lines/ln-<hex>/…`           |

`GET /api/lines` lists them by name, `POST /api/lines {"name"}` makes one,
`PUT /api/lines/<id> {"name"}` renames one; an unknown id gets `404` and
never creates a file. The SPA keeps the Line in its URL,
`/lines/<id>/<view>`, and opens the last one used at `/`.

With `BLUEBIN_SSO=on`, Traefik also copies `X-authentik-email` and
`X-authentik-name`, and each uid is an **Account** in `data/accounts.db`,
shared by every Workspace. `GET /api/account` answers `signedIn`, `named`,
`email`, `firstName` and `lastName`; until `PUT /api/account
{"firstName", "lastName"}` saves them, the SPA shows the first sign-in screen,
with the names suggested from `X-authentik-name`. Without the setting, any
client can send these headers, so the API makes no Account and answers
`{"signedIn": false}`. In dev, the Vite proxy sends all three headers: run the
API with `BLUEBIN_SSO=on gleam run` to see the first sign-in screen.

Only members of the authentik group `bluebin-users` get in. Sign-up is by
invitation only: import [`authentik/bluebin-invitation.yaml`](./authentik/bluebin-invitation.yaml)
once in authentik (Flows and Stages > Flows > Import). The new user joins
`bluebin-users` and lands on bluebin.app.

Bluebin has its own sign-in look: import
[`authentik/bluebin-authentication.yaml`](./authentik/bluebin-authentication.yaml)
the same way. It makes the flow `bluebin-authentication` from the stages of
`default-authentication-flow` and sets it as the authentication flow of the
provider `bluebin`; other apps keep the default sign-in. Both flows use the
`sidebar_left` layout and
[`authentik/bluebin-background.svg`](./authentik/bluebin-background.svg),
which authentik loads from the public Gitea raw URL of `main`. The authentik
brand (logo, favicon, custom CSS) is shared by every app on `auth.apoena.dev`,
so Bluebin does not change it. A user who already has an authentik session
skips the sign-in page.

`akadmin` makes each link with **Invite…** in the header: `POST /api/invitations`
asks authentik for a single-use invitation to `bluebin-invitation`, valid one
week. The API trusts `X-authentik-username` only with `BLUEBIN_SSO=on`, and
needs `AUTHENTIK_TOKEN`: a token with intent "API Token", without expiry, of a
service account with only the global permissions "Can view Flow" and "Can add
Invitation". The token made with the service account is an app password, which
the API refuses as a Bearer token. Without it the API answers `503`, and links are still made in
authentik under Directory > Invitations. In dev, the Vite proxy signs in as
`akadmin`.

**Reset…** acts on
the open Line only: demo data, or one Work Station and one Team Member
to rename in Design.

<!-- docs:start -->

## Documentation

- [CONTEXT.md](./CONTEXT.md) — the ubiquitous language: every domain term and its relationships
- [DESIGN.md](./DESIGN.md) — the QFD design: goals, functions, components and trade-offs
- [ADR-0001](./docs/adr/0001-pieces-never-move-backward.md) — a Piece never moves backward; Rework happens where the defect is found
- [ADR-0002](./docs/adr/0002-flow-event-log-with-current-state.md) — flow event log and current state, written in one transaction
- [ADR-0003](./docs/adr/0003-link-team-members-to-accounts-by-email.md) — Team Members link to Accounts by email, only when SSO is on
- [ADR-0004](./docs/adr/0004-account-links-live-in-one-shared-accounts-db.md) — Accounts and their links live in one shared accounts.db, outside the Line files

<!-- docs:end -->
