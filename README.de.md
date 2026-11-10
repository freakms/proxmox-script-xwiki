# XWiki LXC für Proxmox VE

🇬🇧 [English version](README.md)

Ein einziger Befehl auf dem Proxmox-VE-Host erstellt einen Debian-13-LXC-Container
und installiert darin [XWiki](https://www.xwiki.org), und zwar aus den **offiziellen
XWiki-Debian-Paketen**:

- Debian 13 (trixie), unprivilegierter Container, Nesting aktiv, Autostart
- Apache Tomcat 10 + OpenJDK 21
- PostgreSQL (Standard) oder MariaDB. Datenbank und Benutzer werden automatisch angelegt
- Tomcat-Heap auf ca. 60 % des Container-RAMs eingestellt
- XWiki-Kanal `stable` (Standard, aktuell 18.x) oder `lts`

## Voraussetzungen

- Proxmox VE 8 oder 9, Ausführung als `root` auf der Host-Shell
- Internetzugang für Host und Container
- Mindestens 2 GiB RAM für den Container (empfohlen 4 GiB) und 8 GiB Disk (Standard 16 GiB)

## Schnellstart

Auf der **Shell des Proxmox-VE-Hosts** ausführen:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/freakms/proxmox-script-xwiki/main/xwiki-lxc.sh)"
```

Das Skript fragt die wichtigsten Einstellungen ab, zeigt eine Zusammenfassung
und verlangt eine Bestätigung. Danach im Browser öffnen:

```
http://<container-ip>:8080/xwiki/
```

Der XWiki-**Distribution-Wizard** führt dann durch das Anlegen des
Administrator-Kontos und die Installation des Flavors *XWiki Standard*.

> Lies ein Skript immer, bevor du es in eine Root-Shell pipest. Alternativ kannst
> du das Repository klonen und `./xwiki-lxc.sh` lokal starten. Dann wird
> `install/xwiki-install.sh` aus dem Klon verwendet.

## Unbeaufsichtigte Installation

Alle Einstellungen lassen sich per Umgebungsvariable vorgeben. Mit `--yes`
entfallen alle Rückfragen. Die vollständige Variablenliste steht in der
[englischen README](README.md#unattended-installation) bzw. in `./xwiki-lxc.sh --help`.

```bash
CTID=150 RAM=6144 DISK=32 IP=192.168.1.50/24 GATEWAY=192.168.1.1 DB=mariadb ./xwiki-lxc.sh --yes
```

## Nach der Installation

| Was | Wo |
|-----|----|
| XWiki-Konfiguration | `/etc/xwiki/xwiki.cfg`, `/etc/xwiki/xwiki.properties` |
| Datenbankverbindung | `/etc/xwiki/hibernate.cfg.xml` (von dbconfig-common erzeugt) |
| Permanentes Datenverzeichnis | `/var/lib/xwiki/data` |
| Tomcat-Heap / Java-Optionen | `/etc/default/tomcat10` (Block `proxmox-script-xwiki`) |
| Logs | `journalctl -u tomcat10`, `/var/log/tomcat10/` |

**Updates:** XWiki ist ein normales Debian-Paket. Updates kommen per
`apt update && apt full-upgrade` im Container. Vorher die
[Release Notes](https://www.xwiki.org/xwiki/bin/view/ReleaseNotes/) lesen und ein
Backup oder einen Snapshot erstellen (`vzdump` / Proxmox Backup Server).

**Reverse Proxy / HTTPS:** Für den Produktivbetrieb sollte XWiki hinter einem
Reverse Proxy mit TLS laufen (z. B. nginx, Caddy, Traefik).

## Lizenz

Die Skripte in diesem Repository stehen unter der [MIT-Lizenz](LICENSE).

Die Skripte **enthalten und verbreiten XWiki nicht** und auch keine andere
Fremdsoftware. Sie installieren sie aus den offiziellen Upstream-Quellen, und
jede Komponente behält ihre eigene Lizenz, z. B. XWiki unter der
**GNU LGPL v2.1**. Details und Markenhinweise stehen in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Haftungsausschluss

Dies ist ein unabhängiges Community-Projekt. Es steht **in keiner Verbindung zu
XWiki SAS oder Proxmox Server Solutions GmbH** und wird von diesen weder
unterstützt noch gesponsert. XWiki ist eine Marke der XWiki SAS. Proxmox ist eine
eingetragene Marke der Proxmox Server Solutions GmbH. Die Software wird „wie
besehen“ ohne jegliche Gewährleistung bereitgestellt (siehe [LICENSE](LICENSE)).
