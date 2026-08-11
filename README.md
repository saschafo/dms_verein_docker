# Vereinsverwaltung — Docker-Setup (Frappe Framework 16)

Fertiges Docker-Compose-Setup für die App
[**dms_verein**](https://github.com/saschafo/dms_verein) (Vereins- und
Mitgliederverwaltung) auf **Frappe Framework 16**.

Der Build holt sich die App selbst aus GitHub und backt sie zusammen mit Frappe
fest ins Image. Es braucht nichts weiter als Docker — kein bench, kein Python,
kein Node auf dem Rechner.

Läuft nativ auf **arm64 (Apple Silicon)** und **amd64**.

---

## Schnellstart

```bash
git clone https://github.com/saschafo/dms_verein_docker.git
cd dms_verein_docker

cp .env.example .env     # mindestens ADMIN_PASSWORD und DB_PASSWORD setzen
./build.sh               # Image bauen (beim ersten Mal ~10–20 Min)
./verein.sh up           # Stack starten, Site wird automatisch angelegt
```

Voraussetzung: Docker Engine **23.0+** mit Compose v2 (der Build nutzt
BuildKit-Secrets).

Danach im Browser:

| | |
|---|---|
| URL | <http://localhost:8080> |
| Benutzer | `Administrator` |
| Passwort | Wert von `ADMIN_PASSWORD` aus der `.env` |

Stoppen mit `./verein.sh down` — die Daten bleiben in den Docker-Volumes.

---

## Was hier drin ist

| Datei | Zweck |
|---|---|
| `Containerfile` | Baut das Image: Frappe 16 + dms_verein, Assets vorgebaut |
| `compose.yaml` | Der komplette Stack (siehe unten) |
| `.env` / `.env.example` | Sämtliche Konfiguration (Versionen, Repo, Passwörter, Port) |
| `build.sh` | Image-Build, erzeugt `apps.json` aus der `.env` |
| `verein.sh` | Bedienhilfe: up/down/logs/bench/backup/update/reset |
| `resources/` | nginx-Template und Entrypoints (aus `frappe_docker`) |
| `apps-local/` | Arbeitskopie des App-Repos bei `APP_SOURCE=local` (nicht im Git) |

### Dienste im Stack

| Dienst | Aufgabe |
|---|---|
| `db` | MariaDB 11.8 |
| `redis-cache`, `redis-queue` | Cache bzw. Job-Queue |
| `configurator` | Einmal-Job: schreibt `common_site_config.json` |
| `create-site` | Einmal-Job: legt die Site an, installiert `dms_verein` und aktiviert den Scheduler; bei jedem weiteren Start läuft stattdessen `bench migrate` |
| `backend` | Gunicorn (Frappe-Webserver) |
| `frontend` | nginx, veröffentlicht Port `8080` |
| `websocket` | Socket.IO für Realtime (Chat, Benachrichtigungen) |
| `scheduler` | Zeitgesteuerte Jobs |
| `queue-short`, `queue-long` | Hintergrund-Worker |

Die Einmal-Jobs sind idempotent: `./verein.sh up` kann jederzeit erneut
laufen, ohne die Site zu beschädigen.

---

## Konfiguration

Alles läuft über die `.env`. Die wichtigsten Werte:

```dotenv
APP_SOURCE=git               # git = Build klont selbst | local = eigener Stand
APP_REPO_URL=https://github.com/saschafo/dms_verein
APP_BRANCH=main
APP_NAME=dms_verein          # muss dem app_name aus hooks.py entsprechen

FRAPPE_BRANCH=version-16     # oder ein festes Tag, z. B. v16.30.0
SITE_NAME=verein.localhost
HTTP_PUBLISH_PORT=8080
ADMIN_PASSWORD=...
DB_PASSWORD=...
```

`FRAPPE_SITE_NAME_HEADER` steht auf dem Site-Namen. Dadurch ist die Site unter
jedem Hostnamen erreichbar (`localhost`, `verein.localhost`, IP des Rechners).
Für Mehr-Site-Betrieb stattdessen auf `$$host` setzen.

Die `.env` enthält Passwörter und ist per `.gitignore` vom Repository
ausgeschlossen. Vorlage ist `.env.example`.

---

## Eigenen App-Stand bauen

Wer an der App selbst arbeitet, will einen Stand testen, bevor er gepusht ist.
Dafür gibt es `APP_SOURCE=local`:

```dotenv
APP_SOURCE=local
APP_REPO_URL_HOST=git@github.com:saschafo/dms_verein.git   # optional, z. B. für SSH
```

`build.sh` klont die App dann auf dem **Host** nach `apps-local/dms_verein` und
kopiert das Verzeichnis in den Build. Ein vorhandener Ordner wird verwendet, wie
er ist — dort kann also frei entwickelt werden.

> **Wichtig:** Auch in diesem Modus klont `bench` aus dem Repo. Ein `git clone`
> überträgt nur **committete** Stände — Änderungen, die nur im Arbeitsbaum
> liegen, landen nicht im Image. `build.sh` warnt darum bei unsauberer
> Arbeitskopie und zeigt den gebauten Commit-Hash an.

Ist das App-Repo **privat**, einen Personal Access Token in `APP_REPO_TOKEN`
eintragen. Der Token wird als BuildKit-Secret übergeben und landet damit
**nicht** in den Image-Layern (`docker image history`).

---

## Häufige Aufgaben

```bash
./verein.sh status                 # Container-Status
./verein.sh logs backend           # Logs eines Dienstes
./verein.sh bench --site verein.localhost list-apps
./verein.sh migrate                # Schema-Migration nachziehen
./verein.sh backup                 # Backup inkl. Dateien nach ./backups/
./verein.sh console                # Frappe-Python-Konsole
./verein.sh shell                  # Shell im Backend-Container
./verein.sh reset                  # ALLES löschen (fragt nach)
```

### App-Änderungen übernehmen

Das Image ist unveränderlich — Code-Änderungen kommen ausschließlich über einen
neuen Build hinein:

```bash
git push                 # im App-Repo
./verein.sh update       # baut das Image neu, startet neu, migriert
```

---

## Produktivbetrieb

Für den Einsatz auf einem Server zusätzlich beachten:

1. **Passwörter** in der `.env` ersetzen (`ADMIN_PASSWORD`, `DB_PASSWORD`).
2. **TLS**: einen Reverse Proxy (Traefik, Caddy, nginx-proxy) vor `frontend`
   setzen und `HTTP_PUBLISH_PORT` nur an `127.0.0.1` binden. Fertige Overrides
   dafür liegen im Upstream-Repo `frappe_docker` unter `overrides/`.
3. **Site-Name** auf die echte Domain setzen (`SITE_NAME`,
   `FRAPPE_SITE_NAME_HEADER`) — der Site-Ordner muss so heißen wie die Domain.
4. **Registry**: Image einmal bauen, pushen und auf dem Server nur noch ziehen —
   `CUSTOM_IMAGE=ghcr.io/<user>/dms-verein`, `PULL_POLICY=always`.
5. **Backups** regelmäßig wegsichern (`./verein.sh backup` oder das
   `compose.backup-cron.yaml`-Override aus `frappe_docker`).

---

## Aufbau des Images

`Containerfile` stammt aus dem offiziellen `frappe_docker` (Variante `custom`).
Einzige Abweichung: eine `COPY`-Zeile, die `apps-local/` in die Build-Stage
holt (für `APP_SOURCE=local`; bei `git` ist der Ordner leer und wirkungslos).
Ablauf:

1. Basis: `python:3.14.2-slim-bookworm` + nginx, wkhtmltopdf, Chromium, Node.
2. Build-Stage: `bench init` mit `--apps_path` — klont Frappe (`version-16`)
   und alle Apps aus `apps.json`, installiert Python-Abhängigkeiten und baut
   die Assets.
3. Finale Stage: fertige Bench ohne Build-Werkzeuge, Assets liegen im Image
   und werden beim Start in das `sites`-Volume verlinkt.

`apps.json` wird von `build.sh` aus der `.env` erzeugt, damit die Repo-URL nur
an einer Stelle steht.

Der SPA-Teil der App (`dms_verein/frontend`, Vue 3 + Vite) ist bereits gebaut
im Repository enthalten (`dms_verein/public/frontend`), es wird also kein
zusätzlicher Node-Build-Schritt benötigt.
