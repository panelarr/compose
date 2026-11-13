# Panelarr on one machine

Every Panelarr service in one Docker Compose stack:

| Service | What | Reached at |
|---|---|---|
| `server` | The Panelarr server (library, users, downloads) and its web app | http://localhost:8900 |
| `meta` | The metadata service, and its admin | http://localhost:8901 |
| `meta-mangabaka` | meta's MangaBaka plugin | inside the stack |
| `mihon-source` | Runs Mihon extensions, and its admin | http://localhost:8902 |
| `source-mihon` | The Panelarr source plugin for mihon-source | inside the stack |
| `postgres` | One PostgreSQL server: a database and a role per service (`meta`, `panelarr`) | inside the stack |

Optional, as profiles:

| Profile | Service | What |
|---|---|---|
| `search-typesense` | `typesense` | Search engine for meta (typo-tolerant, multilingual, facet counts) |
| `search-meilisearch` | `meilisearch` | The same with Meilisearch (MIT edition, analytics off) |
| `solver` | `flaresolverr` | Gets past anti-bot challenge pages for providers and sources |
| `vpn` | `gluetun` | A VPN connection offered as an HTTP proxy to the other services |

Ports are published on **127.0.0.1 only**. Nothing else is published: the database, the plugins, the search engines and the helpers are reachable only inside the stack's network.

This folder expects the Panelarr checkouts next to it (`../meta`, `../meta-mangabaka`, `../mihon-source`, `../source-mihon`, `../source-api`, `../server`, `../web`): images are built from them until they are published. The server's image embeds the web app from `../web/dist`.

## What you need

- Docker with Compose v2.17 or newer (for `additional_contexts`).
- Disk, roughly: images and build caches 5 GB; meta's database about 7 GB for the full MangaBaka catalogue, plus 4 GB for its dump; Meilisearch about 3 GB or Typesense about 1 GB of RAM if you use one; and your library. Check with `docker system df`.
- RAM: about 3 GB for the core stack (mihon-source is capped at 1 GB).
- Node 24 and pnpm, to build the web app the server embeds (step 2).

## First run

1. **Secrets.** Generate them once:

   ```sh
   ./generate-secrets.sh
   ```

   It writes `.env` (database passwords, meta's admin token, secret keys, plugin and search keys) and `secrets/` (mihon-source's admin token and secret key, and the key the server uses with source-mihon). It never overwrites what exists. Keep both private and back them up with the volumes: the secret keys decrypt what the services store. Optional settings are listed in `.env.example`; add the ones you want to `.env`.

2. **The web app.** The server's image embeds the built app from `../web/dist`:

   ```sh
   (cd ../web && pnpm install --frozen-lockfile && pnpm build)
   ```

   Rebuild it, then the server (`docker compose up -d --build server`), whenever `../web` changes. Without it the server serves a placeholder page. `WEB_DIST` in `.env` points elsewhere if you build it somewhere else.

3. **Build and start** the core stack:

   ```sh
   docker compose up -d --build
   ```

   The first build takes a while (Go, the JVM build of mihon-source with its admin UI, and meta's admin UI). `docker compose ps` shows when everything is up. `source-mihon` can't reach mihon-source's API until step 5.

4. **meta.** Open http://localhost:8901 and sign in with `META_ADMIN_TOKEN` from `.env`.
   - Under **Clients**, create a client for the Panelarr server with the `admin` scope and copy its key (it is shown once).
   - The MangaBaka plugin syncs daily at 03:00 UTC. To fill the catalogue now: **Jobs → Sync mangabaka (dump) → Run now**. The first sync downloads the dump (about 4 GB) and takes several minutes; the Jobs page shows its progress.

5. **mihon-source.** Open http://localhost:8902 and sign in with the token in `secrets/mihon_admin_token.txt`.
   - Add the extension repositories you trust and install extensions.
   - Under **Clients**, create a client with the scopes `sources:read`, `sources:write` and `admin`, and put its key into `secrets/mihon_source_api_key.txt` (replacing the placeholder). Then:

     ```sh
     docker compose up -d --force-recreate source-mihon
     ```

6. **Panelarr.** Open http://localhost:8900. The first-run wizard creates your admin account and connects the metadata service: URL `http://meta:8901` and the client key from step 4. (Or set `PANELARR_META_URL` and `PANELARR_META_KEY` in `.env` and `docker compose up -d server` to fix the connection in the environment.) Next it offers to add the source plugin: URL `http://source-mihon:8904` and the key in `secrets/source_mihon_api_key.txt` (or later, under Admin → Plugins). Until meta's first sync has finished, Panelarr shows as degraded; that's expected.

## Optional parts

**A search engine for meta.** Add to `.env` `META_SEARCH_BACKEND=typesense` (or `meilisearch`) and start with the profile:

```sh
docker compose --profile search-typesense up -d
```

meta builds the index in the background on first start and answers from PostgreSQL until it is ready. You can also switch in meta's admin (**Integrations → Search engine**); settings saved there win over `.env`.

**A challenge solver.** `docker compose --profile solver up -d`, then in meta's and mihon-source's admin (**Integrations**) add a solver at `http://flaresolverr:8191`, put it on a network profile and assign it.

**A VPN as a proxy.** Fill in your provider's settings in `.env` (see `.env.example` and the [gluetun wiki](https://github.com/qdm12/gluetun-wiki)), then `docker compose --profile vpn up -d`. In meta's and mihon-source's admin, use the proxy `http://gluetun:8888` in a network profile for the providers and sources that should go through the VPN. A solver that should solve from the VPN's address too goes on the same profile.

Several profiles combine: `docker compose --profile solver --profile vpn up -d`. Set `COMPOSE_PROFILES=solver,vpn` in `.env` to make them the default.

## Reaching Panelarr from other devices

Set `APP_BIND=0.0.0.0` in `.env` and `docker compose up -d server`. Anything beyond your LAN needs TLS: put a reverse proxy in front of port 8900 and set `PANELARR_BASE_URL=https://…`. Keep the admin ports (8901, 8902) local; reach them through SSH or a VPN if needed.

## Single sign-on (optional)

Users can sign in with your own OpenID Connect provider next to their password. No provider is bundled; it stays off until you set `PANELARR_OIDC_ISSUER`. Every setting is in the server's [configuration docs](https://github.com/panelarr/server/blob/main/docs/configuration.md#single-sign-on-oidc).

1. Panelarr needs its public URL: set `PANELARR_BASE_URL` (see above).
2. At your provider, register a client (confidential, authorization code flow) with the redirect URI `<PANELARR_BASE_URL>/api/v1/auth/oidc/callback`, e.g. `https://panelarr.example.com/api/v1/auth/oidc/callback`. With `PANELARR_OIDC_LOGOUT=provider`, register `<PANELARR_BASE_URL>/login` as its post-logout redirect URI too.
3. Put the client secret in `secrets/panelarr_oidc_client_secret.txt` (`chmod 644`, like the other files there, so the server's non-root user can read it) and give it to the server as a Docker secret in a `compose.override.yaml` next to `compose.yaml` (Compose reads it automatically):

   ```yaml
   services:
     server:
       secrets: [panelarr_oidc_client_secret]
   secrets:
     panelarr_oidc_client_secret:
       file: ./secrets/panelarr_oidc_client_secret.txt
   ```

4. Add the issuer, client ID and `PANELARR_OIDC_CLIENT_SECRET_FILE=/run/secrets/panelarr_oidc_client_secret` to `.env` (the commented example in `.env.example`), then `docker compose up -d server`. The login page shows a "Sign in with SSO" button.

Existing users are never matched by name or email: each one links their login on their account page, and invites can be accepted with single sign-on. Password login keeps working, so an admin can always get in when the provider is down. To make single sign-on the way in for everyone else, link every user first, then set `PANELARR_OIDC_LOCAL_LOGIN=admins`; a user who hasn't linked is locked out (or, with auto-provisioning on, gets a second, empty account). With `PANELARR_OIDC_ADMIN_GROUPS` set, the provider decides who is admin: every single sign-on sets the user's role from those groups, overriding roles set in Panelarr (the last admin is never demoted).

## Day to day

```sh
docker compose ps                       # status and health
docker compose logs -f server meta      # logs
docker compose pull --ignore-buildable  # update the third-party images
docker compose up -d --build            # rebuild Panelarr's images from the checkouts and restart
docker compose down                     # stop (volumes stay)
```

Back up the volumes `postgres`, `meta`, `mihon-data`, `panelarr-config` and `panelarr-data`, together with `.env` and `secrets/`. Compose names them with the project prefix (`panelarr_postgres`, …); `docker volume ls` lists them. meta's dump volume (`mangabaka`) and the search engines' volumes can be rebuilt.

## Files

| Path | What |
|---|---|
| `compose.yaml` | The stack |
| `generate-secrets.sh` | Creates `.env` and `secrets/` |
| `.env.example` | Optional settings |
| `compose.override.yaml` | Your own additions, e.g. the single sign-on secret (not in git) |
| `meta/meta.yaml` | meta's configuration: the MangaBaka provider, its schedule, the duplicates job |
| `postgres/10-databases.sh` | Creates the roles and databases on the first start |
