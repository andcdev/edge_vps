#!/bin/sh
# Crea le reti tra l'edge e i siti, se non esistono. Si puo' rilanciare.
#
# Sottoreti fisse e fuori dagli intervalli che Docker assegna da solo
# (172.17-31.x, 192.168.x): i siti sanno cosi' da quale indirizzo arriva
# l'edge e si fidano solo di lui per l'IP reale del visitatore.
#
# Un sito nuovo: una riga qui, una rete in docker-compose.yml, un blocco nel
# Caddyfile.
set -e

rete() {
  if docker network inspect "$1" >/dev/null 2>&1; then
    echo "  $1: c'e' gia'"
  else
    docker network create --subnet "$2" "$1" >/dev/null
    echo "  $1: creata ($2)"
  fi
}

rete proxy-magopdf 10.201.0.0/24
rete proxy-lsf     10.201.1.0/24
rete proxy-posta   10.201.2.0/24
