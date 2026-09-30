# Bot Mode MVP (mobile)

**Status:** implemented on this branch — roster + canonical Bot Chat only.  
**Contract:** a bot **is** a Hermes profile; the bot’s primary chat is the forever-session
titled exactly `Bot Chat`. Identity is `(profile, title == "Bot Chat")` — no session-id pin.
Mobile stays a thin remote client.

## UX

- When `/api/profiles` is available, the home sidebar has a **Sessions | Bots** control.
- **Bots** lists every profile (`HermesProfileClient.list`). Tap a row → ensure/open that
  profile’s canonical Bot Chat, then seat the existing `ChatFeature` (one live slot; opening
  another bot tears the previous down — #90 is out of scope).
- **Add bot** reuses `AddProfileFeature` (name + optional SOUL.md, clone-from-default). After
  create, mobile selects the new profile (device-local pref only — never `POST /api/profiles/active`)
  and opens/creates its Bot Chat.
- Canonical `"Bot Chat"` rows are **hidden from the Sessions list and search** when profiles
  exist, so Bot Mode is the door. Cron / archived are unchanged. Older agents without
  profiles keep today’s list (no Bots tab, Bot Chat stays visible if it exists).

## Protocol assumptions

Desktop resolves via gateway `session.list { title: "Bot Chat", include_hidden: true, profile }`.
Mobile mirrors that RPC on a **short-lived** WebSocket (a separate `HermesGatewayClient`
instance — never the chat slot's shared socket):

1. Connect → wait for `gateway.ready` → `session.list` with exact `title: "Bot Chat"`,
   `include_hidden: true`, and the tapped `profile` (including `"default"`).
2. Exact-title match → **adopt** (`session.resume` on `resolved_id` / tip when present).
3. Successful list + no match → **mint** (`session.create` with `title: "Bot Chat"`,
   `hidden: true`) — **no intro / kickoff prompt**. The user speaks first.
4. Any lookup transport/RPC failure → **fail closed**. Never mint a second Bot Chat.

REST `GET /api/profiles/sessions?include_hidden=true` is **not** the registry: the dashboard
endpoint ignores `include_hidden` / `title` and returns only visible rows, which made an
empty success look like "no Bot Chat" and forked a second forever-chat. Do not reintroduce
that path.

If `session.create` rejects `hidden`, the mint retries once without it.

`bot_mode_protocol` decodes on `Profile` when the agent sends it. Create writes the user’s
SOUL.md only — we never append teammate-messaging protocol text.

## Known gaps / deferred

- Gateway `profiles.list` (`canonical_session`, `ui_meta`) — unused; open still uses title RPC.
- REST title/`include_hidden` on `/api/profiles/sessions` — still absent server-side; mobile
  does not depend on it.
- Group chats / multi-round orchestration.
- Cross-connection `bot_relay` / Desktop-as-router.
- Multi-slot sockets (#90).
- Avatar/pet generation; `profiles.describe` / `configure` editors.
- `message_agent` / @mention composer.
- Routines UI filtered to `[bot:]` cron jobs.
- Home mode is in-memory (not persisted).
- DemoMode stubs the Bot Chat registry (no network). A Bots tap in a screenshot
  scenario seats a mint that never becomes `.ready` (demo socket is inert).
