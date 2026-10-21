#!/usr/bin/env bash
#
# PHP2Shell (CVE-2026-109618/109619), messo il 21/10/2026.
#
# COSA ASPETTA. L'immagine roundcube/roundcubemail porta dentro il suo PHP, e
# al 21/10 era ancora 8.4.26, vulnerabile. Nel frattempo il Dockerfile della
# webmail spegne session.upload_progress (zz-php2shell.ini), che e' il punto
# d'attacco. Ogni ora questo script guarda se roundcube ha un'immagine 1.7 con
# PHP >= 8.4.27: prima la stessa versione che usiamo, poi l'ultima della 1.7.
#
# COSA FA QUANDO C'E'. Ricostruisce la webmail su quell'immagine, controlla
# PHP e che il sito risponda 200, poi committa Dockerfile e compose e prova a
# pushare. Se qualcosa va storto torna all'immagine e ai file di prima. In
# tutti e due i casi spegne il proprio timer: non riprova all'infinito.
#
# Le copie di sicurezza stanno in /var/backups/posta-webmail, fuori dal repo:
# un file in piu' in /opt/edge bloccherebbe edge-aggiorna.
#
# Uso:
#   posta-webmail-php2shell                 una passata sola, adesso
#   ./webmail-php2shell.sh --installa       si copia in /usr/local/sbin e accende il timer
#   ./webmail-php2shell.sh --disinstalla    spegne il timer
#   journalctl -u posta-webmail-php2shell   com'e' andata
#
set -u

NOME=posta-webmail-php2shell
BASE=${EDGE_BASE:-/opt/edge}
MINIMO=8.4.27
SITO=https://webmail.listaspesafacile.com/
COPIE=/var/backups/posta-webmail

case "${1:-}" in
  --installa)
    install -m 755 "$0" /usr/local/sbin/$NOME
    cat >/etc/systemd/system/$NOME.service <<EOF
[Unit]
Description=Webmail: aspetta Roundcube con PHP corretto (PHP2Shell)
After=docker.service
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/$NOME
EOF
    cat >/etc/systemd/system/$NOME.timer <<EOF
[Unit]
Description=Ogni ora: Roundcube con PHP corretto?
[Timer]
OnBootSec=10min
OnUnitActiveSec=1h
RandomizedDelaySec=5min
[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now $NOME.timer
    exit 0 ;;
  --disinstalla)
    systemctl disable --now $NOME.timer
    exit 0 ;;
esac

cd "$BASE/posta" || exit 1
IMMAGINE=$(sed -n 's/^ *image: \(posta-webmail:.*\)$/\1/p' docker-compose.yml)

php_ok() {
  docker run --rm --entrypoint php "$1" \
    -r "echo version_compare(PHP_VERSION,'$MINIMO','>=')?'si':'no';" 2>/dev/null
}
fine() { echo "$1"; systemctl disable --now $NOME.timer; exit "${2:-0}"; }

SCELTA=""
for t in 1.7.4-apache 1.7.x-apache; do
  docker pull -q "roundcube/roundcubemail:$t" >/dev/null 2>&1 || continue
  if [ "$(php_ok roundcube/roundcubemail:$t)" = si ]; then SCELTA=$t; break; fi
done
if [ -z "$SCELTA" ]; then
  echo "ancora nessuna immagine roundcube con PHP >= $MINIMO"
  exit 0
fi

# Il numero vero di Roundcube, per fissarlo nel Dockerfile invece di "1.7.x".
V=$(docker run --rm --entrypoint sh "roundcube/roundcubemail:$SCELTA" -c \
  "sed -n \"s/.*RCMAIL_VERSION', '\\([^']*\\)'.*/\\1/p\" /usr/src/roundcubemail/program/include/iniset.php")
[ -n "$V" ] || fine "non riesco a leggere la versione di roundcube in $SCELTA" 1
echo "trovata roundcube $V con PHP corretto ($SCELTA)"

mkdir -p $COPIE
cp -a webmail/Dockerfile $COPIE/Dockerfile
cp -a docker-compose.yml $COPIE/docker-compose.yml
docker tag "$IMMAGINE" posta-webmail:prima-aggiornamento

torna_indietro() {
  cp -a $COPIE/Dockerfile webmail/Dockerfile
  cp -a $COPIE/docker-compose.yml docker-compose.yml
  docker tag posta-webmail:prima-aggiornamento "$IMMAGINE"
  docker compose up -d --force-recreate --no-deps webmail
  fine "$1: tornato all'immagine di prima ($IMMAGINE)" 1
}

sed -i "s|^FROM roundcube/roundcubemail:.*|FROM roundcube/roundcubemail:$V-apache|" webmail/Dockerfile
sed -i "s|^\( *image: \)posta-webmail:.*|\1posta-webmail:$V|" docker-compose.yml

docker compose build --pull webmail || torna_indietro "build fallita"
docker compose up -d --force-recreate --no-deps webmail || torna_indietro "avvio fallito"
sleep 30

PHPV=$(docker exec posta-webmail php -r 'echo PHP_VERSION;' 2>/dev/null)
CODICE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$SITO")
echo "webmail: roundcube $V, PHP $PHPV, $SITO -> $CODICE"
[ "$(php_ok "posta-webmail:$V")" = si ] || torna_indietro "PHP ancora vecchio ($PHPV)"
[ "$CODICE" = 200 ] || torna_indietro "la webmail risponde $CODICE"

# Il repo deve tornare pulito, o edge-aggiorna si ferma.
cd "$BASE"
git add posta/webmail/Dockerfile posta/docker-compose.yml
git -c user.name=andcdev -c user.email=andcecere@gmail.com commit -q \
  -m "Posta: webmail su Roundcube $V (PHP $PHPV, corregge PHP2Shell)" \
  || fine "webmail aggiornata, ma il commit non e' riuscito: committare a mano in $BASE" 1
if git push -q origin HEAD:main; then
  fine "fatto: webmail aggiornata, committata e pushata. La riga zz-php2shell.ini nel Dockerfile si puo' togliere."
else
  fine "fatto: webmail aggiornata e committata, ma il push non e' riuscito: pushare a mano da $BASE" 1
fi
