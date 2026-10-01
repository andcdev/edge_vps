#!/bin/bash
# Stalwart usa per SMTP e IMAP il certificato che l'edge (Caddy) ottiene e rinnova per mail.listaspesafacile.com.
# Questo script lo copia in tls/ (leggibile solo dall'utente 2000 di Stalwart) e, se è cambiato, lo fa
# ricaricare senza fermare niente. La prima volta lo registra in Stalwart come certificato predefinito.
# Da lanciare con regolarità: ./certificato.sh --installa crea posta-certificato.timer (ogni 12 ore).
set -euo pipefail
cd "$(dirname "$0")"
NOME=mail.listaspesafacile.com

if [ "${1:-}" = "--installa" ]; then
  cat > /etc/systemd/system/posta-certificato.service <<UNIT
[Unit]
Description=Copia a Stalwart il certificato di $NOME preso dall'edge
After=docker.service

[Service]
Type=oneshot
ExecStart=$(pwd)/certificato.sh
UNIT
  cat > /etc/systemd/system/posta-certificato.timer <<'UNIT'
[Unit]
Description=Controlla due volte al giorno il certificato della posta

[Timer]
OnBootSec=5min
OnUnitActiveSec=12h
Persistent=true

[Install]
WantedBy=timers.target
UNIT
  systemctl daemon-reload
  systemctl enable --now posta-certificato.timer
  echo "installato: posta-certificato.timer"
  exit 0
fi

DIR=$(docker volume inspect edge_caddy_data -f '{{.Mountpoint}}')/caddy/certificates
CRT=$(find "$DIR" -path "*/$NOME/$NOME.crt" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
if [ -z "$CRT" ]; then
  echo "l'edge non ha ancora un certificato per $NOME (manca il record DNS?)"
  exit 0
fi
KEY=${CRT%.crt}.key
cmp -s "$CRT" tls/cert.pem && cmp -s "$KEY" tls/key.pem && exit 0

install -d -o 2000 -g 2000 -m 700 tls
install -o 2000 -g 2000 -m 600 "$CRT" tls/cert.pem
install -o 2000 -g 2000 -m 600 "$KEY" tls/key.pem

if ./cli.sh query Certificate 2>/dev/null | grep -q "$NOME"; then
  ./cli.sh create Action/ReloadTlsCertificates --json '{}' >/dev/null
  echo "certificato di $NOME aggiornato e ricaricato"
else
  ./cli.sh create Certificate --json '{"certificate": {"@type": "File", "filePath": "/tls/cert.pem"},
    "privateKey": {"@type": "File", "filePath": "/tls/key.pem"}}' >/dev/null
  id=$(./cli.sh query Certificate 2>/dev/null | awk -v t="$NOME" 'NR > 1 && index($0, t) { print $1; exit }')
  ./cli.sh update SystemSettings --json "{\"defaultCertificateId\": \"$id\"}" >/dev/null
  ./cli.sh create Action/ReloadTlsCertificates --json '{}' >/dev/null
  echo "certificato di $NOME registrato in Stalwart (predefinito)"
fi
