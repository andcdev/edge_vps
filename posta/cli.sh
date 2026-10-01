#!/bin/sh
# stalwart-cli verso il server, con la chiave API di .chiave-api (vale solo da 10.201.2.0/24, cioè da qui) o, se
# manca, con utente e password dell'amministratore da .env. Mai sulla riga di comando. La chiave serve perché con
# la verifica in due passaggi (TOTP) sull'amministratore la sola password non basta più.
#   ./cli.sh query Domain
#   ./cli.sh get Domain <id>
set -e
cd "$(dirname "$0")"
CREDENZIALI=.env
[ -s .chiave-api ] && CREDENZIALI=.chiave-api
exec docker run --rm -i --network proxy-posta --env-file "$CREDENZIALI" -e STALWART_URL=http://10.201.2.10:8080 \
  ghcr.io/stalwartlabs/cli:1.0.13 --no-color "$@"
