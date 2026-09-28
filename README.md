# edge_vps

Il proxy davanti a tutti i siti della VPS `89.58.9.88`: un Caddy che è l'**unico container con porte
pubbliche** (80, 443, 443/udp, 8443). Fa tre cose: certificati HTTPS automatici per ogni dominio, smistamento
per nome, redirect da `www`. Le regole di ogni sito (chiavi, noindex, header, CSP) restano nel suo stack.

```
Internet :80 :443 :8443 ──► edge (Caddy, /opt/edge)
   magopdf.com, www        → https://magopdf-fe-web:443    rete proxy-magopdf  10.201.0.0/24
   magopdf.com:8443        → https://magopdf-fe-web:8443   (pannelli)
   listaspesafacile.com    → http://lsf-caddy:80           rete proxy-lsf      10.201.1.0/24
   api.listaspesafacile.com→ http://lsf-caddy:80
   www.listaspesafacile.com→ 301 listaspesafacile.com
   IP nudo, altri nomi     → connessione chiusa
```

Ogni sito ha il suo stack, i suoi repository e una rete sua verso l'edge: gli stack non si vedono tra loro.
Fermare o aggiornare un sito non tocca gli altri (il suo dominio risponde 502 finché non torna).
Se si ferma l'edge si fermano tutti: è piccolo e riparte in un secondo, ma è il pezzo da tenere d'occhio.

| File | |
|---|---|
| `Caddyfile` | un blocco per dominio |
| `docker-compose.yml` | il container, le porte, le reti dei siti |
| `reti.sh` | crea le reti `proxy-*` con sottoreti fisse (una volta sola, si può rilanciare) |

Le sottoreti fisse servono ai siti per fidarsi dell'`X-Forwarded-For` solo quando arriva dall'edge
(MagoPDF: `PROXY_SUBNET` → `set_real_ip_from` in nginx). L'edge scrive l'IP vero del client e scarta quello
che il client aveva messo di suo.

## Comandi

```bash
docker compose logs -f --tail=50                     # accessi (JSON) ed errori, certificati compresi
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile   # dopo aver cambiato il Caddyfile, senza fermo
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile
```

## Aggiungere un sito

1. DNS del dominio → `89.58.9.88`.
2. `reti.sh`: una riga `rete proxy-<sito> 10.201.N.0/24`, e la rete in `docker-compose.yml`. Poi `./reti.sh` e
   `docker compose up -d` (ricrea l'edge: pochi secondi di fermo per tutti; evitabile con
   `docker network connect proxy-<sito> edge-caddy`).
3. Lo stack del sito entra in `proxy-<sito>` senza pubblicare porte, con un nome (alias) noto.
4. Nel `Caddyfile`:
   ```
   nuovosito.it {
   	import accessi
   	reverse_proxy nuovosito-web:80
   }
   www.nuovosito.it, http://www.nuovosito.it {
   	import senza-www nuovosito.it
   }
   ```
   e `caddy reload`. Il certificato arriva da solo al primo avvio.

---

## Prima installazione: lo scambio delle porte

Oggi le porte 80/443/8443 sono di `magopdf-fe-web`. Si passa all'edge così, senza fermare niente fino al
passo 4, che costa pochi secondi.

### 0. Controlli (sola lettura)

```bash
docker compose version                    # serve ≥ 2.24.4 (per "!reset" nei docker-compose.edge.yml)
free -h; df -h /; nproc                   # LSF aggiunge 7 container, MySQL da solo 300–500 MB
docker network inspect $(docker network ls -q) -f '{{.Name}} {{range .IPAM.Config}}{{.Subnet}} {{end}}'
ip route | grep '^10\.201\.'              # 10.201.0.0/24 e 10.201.1.0/24 devono essere liberi
dig +short listaspesafacile.com www.listaspesafacile.com api.listaspesafacile.com   # tutti 89.58.9.88
systemctl list-timers | grep -i certbot; crontab -l | grep -i certbot                 # dov'è il rinnovo di oggi
```

### 1. MagoPDF: il ramo `dietro-edge` in `main`

Il ramo aggiunge `docker-compose.edge.yml` (spento), `set_real_ip_from` in nginx e il controllo di salute di
`magopdf-aggiorna` sul nome `magopdf.com` invece di `localhost`. Unito a `main`, l'aggiornamento automatico
lo pubblica entro 5 minuti **senza cambiare niente**: si controlla che sia passato.

```bash
tail -5 /var/log/magopdf-aggiorna.log     # "fatto: pagina 200, api 200"
```

### 2. Edge e reti, senza avviarlo

```bash
git clone git@github.com:andcdev/edge_vps.git /opt/edge && cd /opt/edge
cp .env.example .env
./reti.sh
docker compose pull
```

### 3. Lista Spesa Facile, senza porte pubbliche

Nel suo `.env` (vedi il README di LSF, sezione «Sul VPS»): `COMPOSE_FILE=…:docker-compose.edge.yml`,
`SITE_HOST`, `APP_URL`, `CLIENT_KEY`, `REVERB_PUBLIC_*`, `PHPMYADMIN_PORT=8082`. Poi `docker compose up -d --build`.

Prova dall'interno, prima di esporlo:

```bash
docker run --rm --network proxy-lsf curlimages/curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: listaspesafacile.com' http://lsf-caddy/          # 200
docker run --rm --network proxy-lsf curlimages/curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: api.listaspesafacile.com' http://lsf-caddy/api/config   # 404
docker run --rm --network proxy-lsf curlimages/curl -s -w '\n' -H 'Host: api.listaspesafacile.com' -H "X-App-Key: $CLIENT_KEY" http://lsf-caddy/api/config  # JSON
```

E MagoPDF visto dalla rete dell'edge, collegandolo a caldo (non tocca le porte):

```bash
docker network connect proxy-magopdf magopdf-fe-web
docker run --rm --network proxy-magopdf curlimages/curl -sk -o /dev/null -w '%{http_code}\n' -H 'Host: magopdf.com' https://magopdf-fe-web/   # 200
```

### 4. Lo scambio (pochi secondi di fermo per MagoPDF)

```bash
cd /opt/magopdf/magopdf-fe
printf '\nCOMPOSE_FILE=docker-compose.yml:docker-compose.edge.yml\n' >> .env
docker compose up -d fe-web && (cd /opt/edge && docker compose up -d)
docker logs -f edge-caddy 2>&1 | grep -i 'certificate obtained\|error'   # 5 certificati, qualche secondo ciascuno
```

### 5. Verifiche, da fuori

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://magopdf.com/                     # 200
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' https://www.magopdf.com/  # 301 → magopdf.com
curl -s -o /dev/null -w '%{http_code}\n' https://magopdf.com/api/ping             # 200
curl -s -o /dev/null -w '%{http_code}\n' https://magopdf.com:8443/                # 401 (password dei pannelli)
curl -s -o /dev/null -w '%{http_code}\n' https://listaspesafacile.com/privacy     # 200
curl -s -o /dev/null -w '%{http_code}\n' https://api.listaspesafacile.com/api/config   # 404 senza chiave
curl -sk -o /dev/null -w '%{http_code}\n' https://89.58.9.88/ || echo chiusa       # chiusa
```

Sulla VPS: `magopdf-aggiorna --forza`, poi `tail /var/log/magopdf-aggiorna.log` → `fatto: pagina 200, api 200`.
Nei log di `magopdf-fe-web` gli IP devono essere quelli veri dei visitatori, non `10.201.0.x`.

### 6. Pulizia

Il certificato di `fe-web` ora non lo vede più nessun browser: si spegne il rinnovo di certbot per
`magopdf.com` (timer o cron trovati al passo 0). Non serve altro.

### Tornare indietro

```bash
cd /opt/edge && docker compose down
cd /opt/magopdf/magopdf-fe && sed -i '/^COMPOSE_FILE=/d' .env && docker compose up -d fe-web
```

MagoPDF riprende le sue porte e il suo certificato di prima. LSF resta avviato ma irraggiungibile da fuori.
