# Link Team Members to Accounts by email, only when SSO is on

Status: accepted

The owner links a Team Member to an Account by typing that Account's email on the Team Member in Design. The link takes effect when an Account with that email signs in. We chose this over an invite link, which anyone could forward to another person, and over letting a new Account pick its Team Member from a list, which lets anyone sign in as someone else. Only the owner changes Team Members, so only the owner sets the links.

The email comes from the `X-authentik-email` header. Traefik forward auth writes that header from authentik's answer and drops any value the client sends, so it is trusted only while SSO is on. With SSO off, any client can send any email, so Bluebin links nothing and opens no Workspace other than the one the request already names.

## Considered Options

| Option                                         | Tradeoff                                                               | Outcome  |
| ---------------------------------------------- | ---------------------------------------------------------------------- | -------- |
| Invite link for one Team Member                | Needs no email, but whoever opens the link becomes that Team Member    | Rejected |
| Account picks its Team Member at first sign-in | No owner work, but nothing checks the choice                           | Rejected |
| Email in Design                                | The owner already manages Team Members, and authentik checks the email | Chosen   |

## Consequences

- When an Account's email changes in authentik, its links stop working until the owner types the new email.
- A wrong email links nobody. Design shows which Team Members are not linked yet.
- An Account is at most one Team Member in each Line, so one email can be on at most one Team Member per Line.
