# Roundcube con rcguard (captcha al login, Cloudflare Turnstile). Fork di pbiering: quello di dsoares non ha Turnstile.
FROM roundcube/roundcubemail:1.7.4-apache

ARG RCGUARD=e2f762e50b83d0a2da02711e07dd7fc04dd71e28
RUN curl -fsSL "https://github.com/pbiering/roundcube-rcguard/archive/${RCGUARD}.tar.gz" \
      | tar xz -C /usr/src/roundcubemail/plugins \
 && mv "/usr/src/roundcubemail/plugins/roundcube-rcguard-${RCGUARD}" /usr/src/roundcubemail/plugins/rcguard

# Impostazioni di rcguard: il plugin carica il suo config.inc.php dopo quello di Roundcube, quindi stanno qui.
COPY rcguard.inc.php /usr/src/roundcubemail/plugins/rcguard/config.inc.php
# A ogni avvio, dopo la creazione del database: la tabella di rcguard, se manca.
COPY rcguard-tabella.sh /entrypoint-tasks/post-setup/10-rcguard-tabella.sh
