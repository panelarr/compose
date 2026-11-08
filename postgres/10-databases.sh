#!/bin/sh
# One PostgreSQL server, a database per service, each owned by its own role
# with no other rights, as in production. Runs once, when the data volume is
# empty. The passwords come from .env (see generate-secrets.sh).
set -eu

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<EOSQL
CREATE ROLE meta LOGIN PASSWORD '${META_DB_PASSWORD}';
CREATE DATABASE meta OWNER meta;
REVOKE ALL ON DATABASE meta FROM PUBLIC;

CREATE ROLE panelarr LOGIN PASSWORD '${PANELARR_DB_PASSWORD}';
CREATE DATABASE panelarr OWNER panelarr;
REVOKE ALL ON DATABASE panelarr FROM PUBLIC;
EOSQL

# PostgreSQL 15+ gives only the owner CREATE on public; nothing else to do.
