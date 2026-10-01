#!/bin/sh
# stalwart-cli verso il server, con le credenziali dell'amministratore lette da .env (mai sulla riga di comando).
#   ./cli.sh query Domain
#   ./cli.sh get Domain <id>
set -e
cd "$(dirname "$0")"
exec docker run --rm -i --network proxy-posta --env-file .env -e STALWART_URL=http://10.201.2.10:8080 \
  ghcr.io/stalwartlabs/cli:1.0.13 --no-color "$@"
