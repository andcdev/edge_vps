#!/bin/bash
# Configurazione di Stalwart dopo primo-avvio.sh. Si può rilanciare: crea solo quello che manca.
#
# - porta 587 (invio con STARTTLS) accanto alla 465 che Stalwart apre già;
# - IP vero dei visitatori del pannello dall'X-Forwarded-For: la 8080 la raggiunge solo l'edge;
# - domini e caselle qui sotto. Le password delle caselle nuove sono casuali e finiscono in caselle.txt (600).
set -euo pipefail
cd "$(dirname "$0")"
umask 077

DOMINI=(listaspesafacile.com magopdf.com)
CASELLE=(support@listaspesafacile.com noreply@listaspesafacile.com support@magopdf.com noreply@magopdf.com)

# Id di un oggetto dalla tabella di "query": prima colonna della riga che contiene il testo cercato.
id_di() { ./cli.sh query "$1" 2>/dev/null | awk -v t="$2" 'NR > 1 && index($0, t) { print $1; exit }'; }

if ./cli.sh query NetworkListener 2>/dev/null | grep -qw submission; then
  echo "porta 587: c'è già"
else
  ./cli.sh create NetworkListener --stdin >/dev/null <<'JSON'
{"name": "submission", "bind": {"[::]:587": true}, "protocol": "smtp", "useTls": true, "tlsImplicit": false}
JSON
  docker compose restart stalwart >/dev/null   # un listener nuovo parte solo al riavvio
  sleep 5
  echo "porta 587: creata"
fi

./cli.sh update Http --json '{"useXForwarded": true}' >/dev/null
echo "X-Forwarded-For dall'edge: attivo"

for d in "${DOMINI[@]}"; do
  if [ -n "$(id_di Domain " $d ")" ]; then
    echo "dominio $d: c'è già"
  else
    ./cli.sh create Domain --json "{\"name\": \"$d\"}" >/dev/null
    echo "dominio $d: creato (chiavi DKIM generate da Stalwart)"
  fi
done

for c in "${CASELLE[@]}"; do
  nome=${c%@*} dominio=${c#*@}
  if [ -n "$(id_di Account " $c ")" ]; then
    echo "casella $c: c'è già"
    continue
  fi
  did=$(id_di Domain " $dominio ")
  [ -n "$did" ] || { echo "dominio $dominio mancante"; exit 1; }
  pw=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
  ./cli.sh create Account/User --stdin >/dev/null <<JSON
{"name": "$nome", "domainId": "$did", "credentials": {"0": {"@type": "Password", "secret": "$pw"}}}
JSON
  printf '%s\t%s\n' "$c" "$pw" >> caselle.txt
  echo "casella $c: creata, password in $(pwd)/caselle.txt"
done

# postmaster@ e abuse@ (obbligatori per le RFC; ci arrivano anche i rapporti DMARC e TLS) come alias di support@.
for d in "${DOMINI[@]}"; do
  aid=$(id_di Account " support@$d ") did=$(id_di Domain " $d ")
  ./cli.sh update Account "$aid" --json "{\"aliases\": {\"0\": {\"name\": \"postmaster\", \"domainId\": \"$did\"}, \"1\": {\"name\": \"abuse\", \"domainId\": \"$did\"}}}" >/dev/null
  echo "postmaster@$d e abuse@$d: alias di support@$d"
done

./cli.sh create Action/ReloadSettings --json '{}' >/dev/null 2>&1 || true
