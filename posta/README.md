# Posta

Server di posta della VPS: [Stalwart](https://stalw.art) v0.16, un container solo, per **listaspesafacile.com** e
**magopdf.com**. Nome del server: `mail.listaspesafacile.com` (anche per magopdf.com).

```
Internet :25 :465 :587 :993 ──► posta-stalwart (porte pubblicate da Docker, solo IPv4)
Internet :443 mail.listaspesafacile.com ──► edge (Caddy) ──► posta-stalwart:8080   rete proxy-posta 10.201.2.0/24
                                                                                    (pannello /admin e /account)
Internet :443 webmail.listaspesafacile.com ──► edge ──► posta-webmail:80 (Roundcube, 10.201.2.20)
                                                         └─ IMAP 993 / SMTP 465 ──► posta-stalwart (rete interna)
```

| Casella | |
|---|---|
| `support@listaspesafacile.com` | alias `postmaster@`, `abuse@` (ci arrivano anche i rapporti DMARC e TLS) |
| `noreply@listaspesafacile.com` | mittente delle email dell'app |
| `support@magopdf.com` | alias `postmaster@`, `abuse@` |
| `noreply@magopdf.com` | mittente delle email di MagoPDF |

Le password delle caselle sono in `caselle.txt`, quella dell'amministratore (`admin@listaspesafacile.com`) in
`.env`: tutti e due solo sulla VPS, permessi 600, fuori da git.

| File | |
|---|---|
| `docker-compose.yml` | il container, le porte, i volumi `etc` (solo config.json) e `dati` (tutto il resto) |
| `primo-avvio.sh` | una volta sola: configurazione iniziale e amministratore in `.env` |
| `configura.sh` | porta 587, domini, caselle, alias. Si può rilanciare: crea solo quello che manca |
| `certificato.sh` | copia a Stalwart il certificato che l'edge ha per `mail.listaspesafacile.com` |
| `cli.sh` | `stalwart-cli` con le credenziali di `.env` (es. `./cli.sh query Account`) |

## Installazione

```bash
cd /opt/edge && ./reti.sh                                # rete proxy-posta
docker network connect proxy-posta edge-caddy            # senza ricreare l'edge (o docker compose up -d)
cd posta && docker compose up -d
./primo-avvio.sh && ./configura.sh
./certificato.sh --installa                              # timer ogni 12 ore
```

Il certificato non lo chiede Stalwart (80 e 443 sono dell'edge): Caddy lo ottiene per il blocco
`mail.listaspesafacile.com` del Caddyfile e `certificato.sh` lo copia in `tls/` e lo fa ricaricare a Stalwart
(`ReloadTlsCertificates`, senza fermo). Finché il record DNS di `mail.` non c'è, non c'è certificato e SMTP/IMAP
non offrono TLS.

## Webmail

Stalwart non ha una webmail (`/account` è solo la gestione dell'account): c'è Roundcube in `webmail/`, su
<https://webmail.listaspesafacile.com>. Si entra con indirizzo completo e password della casella.

- Captcha a ogni login: plugin rcguard (fork di pbiering, l'unico con Turnstile) con Cloudflare Turnstile.
  Chiavi in `webmail.env` (solo sulla VPS, 600) insieme a `ROUNDCUBEMAIL_DES_KEY`. Dopo averle cambiate:
  `docker compose up -d webmail` (un semplice restart non rilegge il file).
- Roundcube parla con Stalwart sulla rete interna, col nome `mail.listaspesafacile.com` mappato su 10.201.2.10
  (`extra_hosts`) perché il certificato sia valido.
- Il suo IP (10.201.2.20) è tra gli `AllowedIp` di Stalwart: altrimenti chi sbaglia la password dalla webmail
  farebbe bannare la webmail per tutti. I tentativi dalla webmail li ferma il captcha.
- Database SQLite nel volume `posta_webmail`; la tabella di rcguard la crea `webmail/rcguard-tabella.sh` all'avvio.

## Perché solo IPv4

Su IPv6 Docker passa dal suo proxy e Stalwart vedrebbe come mittente il gateway, non il vero server: SPF,
liste nere e antispam sbagliati. Quindi `mail.listaspesafacile.com` ha solo il record A e il DNS inverso è
quello dell'IPv4.

## Comandi

```bash
docker compose logs -f --tail=50 stalwart
./cli.sh query Account
./cli.sh get Domain b                       # in fondo: i record DNS che Stalwart si aspetta
```

Una casella nuova: aggiungerla a `CASELLE` in `configura.sh` e rilanciarlo. Una password nuova: dal pannello
`https://mail.listaspesafacile.com/admin`.

## Backup

Tutto è nel volume `posta_dati` (e `posta_etc`). Una copia coerente: `docker compose stop`, copia di
`/var/lib/docker/volumes/posta_dati/_data`, `docker compose start` (la posta in arrivo intanto aspetta: chi manda
riprova).
