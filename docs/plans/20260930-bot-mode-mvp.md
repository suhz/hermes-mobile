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
Mobile has **no standing WebSocket** outside `ChatFeature`, so the registry is REST:

1. `GET /api/profiles/sessions?profile=&include_hidden=true` (paged, cap 500).
2. On 400/404/405, fall back to the visible list and mark `includeHiddenSupported = false`.
3. Exact title match → **adopt** (`session.resume` through `ChatFeature`).
4. Successful hidden list + no match → **mint** (`session.create` with `title: "Bot Chat"`,
   `hidden: true`, plus an optional intro `prompt.submit`).
5. Visible-only list + no match → **fail closed** (`cannotVerifyUniqueness`), except right
   after `profiles.create` (no Bot Chat can exist yet).
6. Any lookup transport/HTTP failure → **fail closed**. Never mint a second Bot Chat.

If `session.create` rejects `hidden`, the mint retries once without it.

`bot_mode_protocol` decodes on `Profile` when the agent sends it. Create writes the user’s
SOUL.md only — we never append teammate-messaging protocol text.

## Known gaps / deferred

- Gateway `session.list` / `profiles.list` (canonical_session, ui_meta) — unused; REST only.
- Title-filter query on REST (we scan pages instead). Hidden Bot Chats older than the 500-row
  cap would be missed.
- Group chats / multi-round orchestration.
- Cross-connection `bot_relay` / Desktop-as-router.
- Multi-slot sockets (#90).
- Avatar/pet generation; `profiles.describe` / `configure` editors.
- `message_agent` / @mention composer.
- Routines UI filtered to `[bot:]` cron jobs.
- Home mode is in-memory (not persisted).
