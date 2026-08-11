#!/usr/bin/env bash
# =============================================================================
# Bedienhilfe für den Vereins-Stack.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "FEHLER: .env fehlt. Anlegen mit:  cp .env.example .env" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

SITE=${SITE_NAME:-verein.localhost}
PORT=${HTTP_PUBLISH_PORT:-8080}

dc() { docker compose "$@"; }

usage() {
  cat <<EOF
Verwendung: ./verein.sh <befehl> [args]

  up                Stack starten (Site wird beim ersten Start angelegt)
  down              Stack stoppen (Daten bleiben erhalten)
  restart           Stack neu starten
  status            Container-Status
  logs [service]    Logs folgen (ohne Angabe: alle)
  bench <args...>   bench im Backend ausführen, z. B. ./verein.sh bench --site $SITE list-apps
  shell             Bash-Shell im Backend-Container
  migrate           bench migrate für $SITE
  update            Image neu bauen, Stack neu starten, migrieren
  backup            Backup inkl. Dateien nach ./backups/
  console           Frappe-Python-Konsole
  reset             ALLES löschen (Container + Volumes, inkl. Datenbank!)
EOF
}

cmd=${1:-}
[[ $# -gt 0 ]] && shift || true

case "$cmd" in
  up)
    dc up -d "$@"
    echo
    echo "Warte auf die Site (das erste Mal dauert es ein paar Minuten) ..."
    dc logs -f create-site || true
    echo
    echo "URL      : http://localhost:${PORT}   (auch: http://${SITE}:${PORT})"
    echo "Benutzer : Administrator"
    echo "Passwort : ${ADMIN_PASSWORD}"
    ;;
  down)     dc down "$@" ;;
  restart)  dc restart "$@" ;;
  status)   dc ps ;;
  logs)     dc logs -f --tail=100 "$@" ;;
  bench)    dc exec backend bench "$@" ;;
  shell)    dc exec backend bash ;;
  console)  dc exec backend bench --site "$SITE" console ;;
  migrate)  dc exec backend bench --site "$SITE" migrate ;;
  update)
    ./build.sh --refresh
    dc up -d --force-recreate
    dc logs -f create-site || true
    ;;
  backup)
    mkdir -p backups
    dc exec backend bench --site "$SITE" backup --with-files
    # Backups liegen im sites-Volume; von dort herauskopieren:
    cid=$(dc ps -q backend)
    docker cp "${cid}:/home/frappe/frappe-bench/sites/${SITE}/private/backups/." ./backups/
    echo "Backups liegen in ./backups/"
    ;;
  reset)
    read -r -p "Wirklich ALLE Daten (Datenbank, Site, Uploads) löschen? [ja/NEIN] " answer
    if [[ "$answer" == "ja" ]]; then
      dc down -v
      echo "Alles entfernt. Neu aufsetzen mit: ./verein.sh up"
    else
      echo "Abgebrochen."
    fi
    ;;
  ""|-h|--help|help) usage ;;
  *)
    echo "Unbekannter Befehl: $cmd" >&2
    echo
    usage
    exit 1
    ;;
esac
