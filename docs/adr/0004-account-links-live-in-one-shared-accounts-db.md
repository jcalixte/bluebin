# Account links live in one shared accounts.db

Status: accepted

Each Line keeps its data in its own SQLite file, but Accounts and the links between a Team Member and an Account live in one shared `data/accounts.db`. We chose this because links cross Lines and Workspaces: listing every Line an Account can open, and checking access on each request, is then one indexed query instead of a scan of every Line file. The two alternatives were the email on the Team Member in the Line file plus a rebuildable index, which keeps two copies to sync, and the email in the Line files only, scanned at sign-in, which slows down as Workspaces grow.

## Consequences

- A link change is not in the Line's transaction or its flow log. `accounts.db` keeps its own dated log of link changes, so every change is still dated (F40).
- A Reset or a removed Team Member leaves orphan links. A link counts only while its Team Member still exists in the Line, so an orphan grants nothing; it is cleaned after the change.
- An Account's first and last name, which belong to no Line, live in the same file.
