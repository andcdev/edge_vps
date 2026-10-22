# Roundcube con rcguard (captcha al login, Cloudflare Turnstile). Fork di pbiering: quello di dsoares non ha Turnstile.
# Fissata al digest: il tag 1.7.5-apache viene ricostruito quando cambia PHP, e una build senza --pull
# riusa la copia locale vecchia (il 22/10/2026 cosi' e' tornato PHP 8.4.26, vulnerabile a PHP2Shell).
# Digest del 22/10/2026: PHP 8.4.27. Per aggiornare: docker pull del tag, poi il digest nuovo qui.
FROM roundcube/roundcubemail:1.7.5-apache@sha256:ebf5271ff6f15fd5939c66b31525ba1bfaefdeae8bc2b69f631e10890b1ad15f

ARG RCGUARD=e2f762e50b83d0a2da02711e07dd7fc04dd71e28
RUN curl -fsSL "https://github.com/pbiering/roundcube-rcguard/archive/${RCGUARD}.tar.gz" \
      | tar xz -C /usr/src/roundcubemail/plugins \
 && mv "/usr/src/roundcubemail/plugins/roundcube-rcguard-${RCGUARD}" /usr/src/roundcubemail/plugins/rcguard

# Impostazioni di rcguard: il plugin carica il suo config.inc.php dopo quello di Roundcube, quindi stanno qui.
COPY rcguard.inc.php /usr/src/roundcubemail/plugins/rcguard/config.inc.php
# A ogni avvio, dopo la creazione del database: la tabella di rcguard, se manca.
COPY rcguard-tabella.sh /entrypoint-tasks/post-setup/10-rcguard-tabella.sh
