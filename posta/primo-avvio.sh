#!/bin/bash
# Primo avvio di Stalwart, una volta sola: completa la configurazione iniziale (nome del server, dominio
# principale, chiavi DKIM, log su console) e salva in .env (permessi 600) l'amministratore che Stalwart crea.
# Nessuna password passa sulla riga di comando o a schermo.
set -euo pipefail
cd "$(dirname "$0")"
[ -s .env ] && { echo ".env c'è già: il primo avvio è già stato fatto"; exit 1; }
umask 077

# Al primo avvio Stalwart scrive nei log una password temporanea per l'utente admin.
P=""
for _ in $(seq 1 30); do
  P=$(docker logs posta-stalwart 2>&1 | sed -n 's/^ *password: *//p' | head -1)
  [ -n "$P" ] && break
  sleep 2
done
[ -n "$P" ] || { echo "password temporanea non trovata nei log di posta-stalwart"; exit 1; }
printf 'STALWART_USER=admin\nSTALWART_PASSWORD=%s\n' "$P" > .env

# Il certificato non lo chiede Stalwart: le porte 80/443 sono dell'edge, che lo ottiene già (certificato.sh).
RISPOSTA=$(./cli.sh update Bootstrap --stdin <<'JSON'
{
  "serverHostname": "mail.listaspesafacile.com",
  "defaultDomain": "listaspesafacile.com",
  "requestTlsCertificate": false,
  "generateDkimKeys": true,
  "tracer": {"@type": "Stdout", "enable": true, "level": "info", "ansi": false, "buffered": false,
             "lossy": false, "multiline": false, "eventsPolicy": "exclude", "events": {}}
}
JSON
)
UTENTE=$(sed -n 's/^ *username: "\(.*\)"$/\1/p' <<<"$RISPOSTA")
SEGRETO=$(sed -n 's/^ *secret: "\(.*\)"$/\1/p' <<<"$RISPOSTA")
if [ -z "$UTENTE" ] || [ -z "$SEGRETO" ]; then
  rm -f .env
  echo "risposta inattesa da Stalwart, niente salvato"
  exit 1
fi
printf 'STALWART_USER=%s\nSTALWART_PASSWORD=%s\n' "$UTENTE" "$SEGRETO" > .env

docker compose restart stalwart >/dev/null
echo "fatto: amministratore $UTENTE, password in $(pwd)/.env"
