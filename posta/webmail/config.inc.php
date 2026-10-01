<?php
// Configurazione di Roundcube per la posta della VPS (montata in /var/roundcube/config, inclusa dall'immagine).

// IMAP e SMTP: Stalwart sulla rete interna. Il nome resta mail.listaspesafacile.com (extra_hosts nel compose)
// perché il certificato sia valido; utente e password sono quelli della casella.
$config['imap_host'] = 'ssl://mail.listaspesafacile.com:993';
$config['smtp_host'] = 'ssl://mail.listaspesafacile.com:465';
$config['smtp_user'] = '%u';
$config['smtp_pass'] = '%p';

$config['product_name'] = 'Webmail';
$config['language'] = 'it_IT';
$config['skin'] = 'elastic';

// Dietro l'edge (Caddy, rete proxy-posta): IP vero del visitatore da X-Forwarded-For, sito in HTTPS.
$config['proxy_whitelist'] = ['10.201.2.0/24'];
$config['use_https'] = true;

// Sessioni: legate all'IP, scadono dopo 30 minuti senza attività.
$config['ip_check'] = true;
$config['session_lifetime'] = 30;

// Il login è solo con l'indirizzo completo; nessun suggerimento sul server.
$config['login_autocomplete'] = 0;
$config['display_product_info'] = 0;
