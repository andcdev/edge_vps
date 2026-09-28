#!/usr/bin/env bash
#
# Porta l'edge all'ultimo main di GitHub. Stesso schema di magopdf-aggiorna.
#
# COME DECIDE. Ogni 5 minuti (timer systemd) confronta il commit locale con
# origin/main. Uguali: esce in silenzio, senza scrivere nel registro.
#
# COSA APPLICA DA SOLO. Solo il Caddyfile, con "caddy reload": nessun
# riavvio, nessun secondo di fermo per nessun sito. Caddy valida il file
# prima di applicarlo e, se e' sbagliato, lo rifiuta e tiene il vecchio.
#
# COSA NON APPLICA. Se cambiano docker-compose.yml o reti.sh (porte, reti,
# un sito nuovo) serve ricreare l'edge, e cioe' fermare per qualche secondo
# tutti i siti: lo si fa a mano, con calma. Il registro lo dice.
#
# LA RETE DI SICUREZZA. Prima e dopo il reload interroga ogni dominio del
# Caddyfile passando dall'edge. Se un dominio che prima rispondeva ora non
# risponde, si torna al commit e al Caddyfile di prima. Un dominio gia' giu'
# prima (il suo sito e' fermo) non fa tornare indietro nessuno.
#
# Uso:
#   edge-aggiorna                 una passata sola, adesso
#   edge-aggiorna --forza         ricarica e controlla anche se non e' cambiato niente
#   edge-aggiorna --stato         cosa c'e' e cosa ci sarebbe, senza toccare
#   ./aggiorna.sh --installa      si copia in /usr/local/sbin e accende il timer
#   ./aggiorna.sh --disinstalla   spegne il timer
#
set -euo pipefail

BASE=${EDGE_BASE:-/opt/edge}
LOG=/var/log/edge-aggiorna.log
LOCK=/var/lock/edge-aggiorna.lock
OGNI=${EDGE_OGNI:-5min}
INSTALLATO=/usr/local/sbin/edge-aggiorna
NOME=edge-aggiorna

dire() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }

installa() {
  [ "$(id -u)" = 0 ] || { echo "serve root: sudo $0 --installa"; exit 1; }
  install -m 755 "$(readlink -f "$0")" "$INSTALLATO"
  cat > /etc/systemd/system/$NOME.service <<CONF
[Unit]
Description=Aggiorna il proxy edge dall'ultimo main di GitHub
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
Environment=EDGE_BASE=${BASE}
ExecStart=${INSTALLATO}
CONF
  cat > /etc/systemd/system/$NOME.timer <<CONF
[Unit]
Description=Controlla ogni ${OGNI} se c'e' un main nuovo per l'edge

[Timer]
OnBootSec=4min
OnUnitActiveSec=${OGNI}
Persistent=true
RandomizedDelaySec=45

[Install]
WantedBy=timers.target
CONF
  systemctl daemon-reload
  systemctl enable --now $NOME.timer
  touch "$LOG"; chmod 640 "$LOG"
  echo "  installato: controlla ogni ${OGNI}"
  echo "  stato:    systemctl list-timers $NOME.timer"
  echo "  registro: tail -f ${LOG}"
  exit 0
}

disinstalla() {
  [ "$(id -u)" = 0 ] || { echo "serve root"; exit 1; }
  systemctl disable --now $NOME.timer 2>/dev/null || true
  rm -f /etc/systemd/system/$NOME.{service,timer}
  systemctl daemon-reload
  echo "  timer spento. Lo script resta in ${INSTALLATO}."
  exit 0
}

stato() {
  cd "$BASE"
  git fetch -q origin main 2>/dev/null || { echo "  GitHub non raggiungibile"; exit 0; }
  if [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]; then
    echo "  edge: aggiornato ($(git rev-parse --short HEAD))"
  else
    echo "  edge: $(git rev-list --count HEAD..origin/main) commit da prendere"
    git log --oneline HEAD..origin/main | sed 's/^/      /'
  fi
  [ -n "$(git status --porcelain)" ] && echo "      ATTENZIONE: modifiche locali, verrebbe saltato"
  exit 0
}

case "${1:-}" in
  --installa)    installa ;;
  --disinstalla) disinstalla ;;
  --stato)       stato ;;
  --forza)       FORZA=1 ;;
  "")            FORZA=0 ;;
  *) echo "opzione sconosciuta: $1"; exit 2 ;;
esac

exec 9>"$LOCK"
flock -n 9 || { echo "un aggiornamento e' gia' in corso"; exit 0; }

cd "$BASE"
if [ -n "$(git status --porcelain)" ]; then
  dire "modifiche locali non committate in $BASE: non aggiorno"
  exit 0
fi
git fetch -q origin main || { dire "non riesco a raggiungere GitHub"; exit 1; }
PRIMA=$(git rev-parse HEAD)
if [ "$PRIMA" = "$(git rev-parse origin/main)" ] && [ "$FORZA" = 0 ]; then
  exit 0
fi

# ----------------------------------------------------------------- i domini
# I nomi dei blocchi del Caddyfile (tranne gli http:// e gli snippet), con la
# loro porta se non e' la 443. Interrogati passando dall'edge, come un
# visitatore: 000 o 5xx = non risponde; 2xx, 3xx, 4xx = il sito c'e'.
domini() {
  grep -E '^[a-z0-9]' caddy/Caddyfile | grep -v '^http://' | sed 's/ *{ *$//' | tr ',' '\n' \
    | sed 's/^ *//; s/ *$//; s#^https://##' | grep -E '^[a-z0-9.-]+\.[a-z]+(:[0-9]+)?$' || true
}
codice() {                         # $1 = dominio[:porta]
  local host=${1%%:*} porta=443
  [ "$1" != "$host" ] && porta=${1##*:}
  curl -s -o /dev/null -m 10 -w '%{http_code}' --resolve "$host:$porta:127.0.0.1" "https://$host:$porta/" || echo 000
}
vivo() { case "$1" in 2??|3??|4??) return 0 ;; *) return 1 ;; esac; }
foto() {                           # "dominio=codice" per ogni dominio
  local d; for d in $(domini); do printf '%s=%s\n' "$d" "$(codice "$d")"; done
}
caricare() { docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile >>"$LOG" 2>&1; }

PRIMA_FOTO=$(foto)

git merge -q --ff-only origin/main || { dire "avanzamento lineare impossibile (rami divergenti), mi fermo"; exit 1; }
DOPO=$(git rev-parse HEAD)
[ "$PRIMA" != "$DOPO" ] && dire "ora a $(git rev-parse --short HEAD) — $(git log -1 --format=%s | cut -c1-60)"

if ! git diff --quiet "$PRIMA" "$DOPO" -- docker-compose.yml reti.sh; then
  dire "ATTENZIONE: cambiati docker-compose.yml o reti.sh — servono a mano: ./reti.sh && docker compose up -d (qualche secondo di fermo per tutti)"
fi

if ! caricare; then
  dire "Caddyfile rifiutato da Caddy: resta in uso quello di prima; torno al commit $PRIMA"
  git reset -q --hard "$PRIMA"
  exit 1
fi

# ---------------------------------------------------------- la prova finale
sleep 3
ROTTI=""
while IFS='=' read -r d prima; do
  [ -n "$d" ] || continue
  vivo "$prima" || continue          # era gia' giu': non e' colpa di questo aggiornamento
  ora=000
  for _ in 1 2 3 4 5; do ora=$(codice "$d"); vivo "$ora" && break; sleep 3; done
  vivo "$ora" || ROTTI="$ROTTI $d($prima→$ora)"
done <<< "$PRIMA_FOTO"

if [ -n "$ROTTI" ]; then
  dire "dopo il reload non rispondono:$ROTTI — torno al commit di prima"
  git reset -q --hard "$PRIMA"
  if caricare; then dire "rientro riuscito"; else dire "RIENTRO FALLITO: serve un intervento a mano"; fi
  exit 1
fi

NUOVO="$BASE/deploy/aggiorna.sh"
if [ -f "$NUOVO" ] && [ -f "$INSTALLATO" ] && ! cmp -s "$NUOVO" "$INSTALLATO"; then
  install -m 755 "$NUOVO" "$INSTALLATO"
  dire "aggiornato anche lo script di aggiornamento"
fi

dire "fatto: $(foto | tr '\n' ' ')"
