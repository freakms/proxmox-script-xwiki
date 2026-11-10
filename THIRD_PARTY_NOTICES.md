# Third-Party Notices

This repository contains **only shell scripts** (MIT licensed, see
[LICENSE](LICENSE)). It does **not** contain, bundle or redistribute any
third-party software. The scripts download and install the software listed
below at run time, directly from the official upstream sources (the Proxmox
template mirror, the Debian archive and the XWiki APT repository).

Each of these components is distributed under its own license. By running the
scripts you obtain the software from its upstream source and you are bound by
the respective license terms. The MIT license of this repository does **not**
apply to the software installed by the scripts.

| Component | Installed from | License |
|-----------|----------------|---------|
| [XWiki](https://www.xwiki.org) (`xwiki-tomcat10-*` packages) | `https://maven.xwiki.org` | [GNU LGPL v2.1](https://www.xwiki.org/xwiki/bin/view/Main/License) |
| [Apache Tomcat 10](https://tomcat.apache.org) | Debian archive | [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0) |
| [OpenJDK](https://openjdk.org) (Java runtime) | Debian archive | [GPL v2 with Classpath Exception](https://openjdk.org/legal/gplv2+ce.html) |
| [PostgreSQL](https://www.postgresql.org) (option `DB=pgsql`) | Debian archive | [PostgreSQL License](https://www.postgresql.org/about/licence/) |
| [MariaDB Server](https://mariadb.org) (option `DB=mariadb`) | Debian archive | [GNU GPL v2](https://mariadb.com/kb/en/mariadb-license/) |
| JDBC driver (PostgreSQL / MariaDB Connector/J) | Debian archive | BSD-2-Clause / GNU LGPL v2.1 |
| [Debian GNU/Linux 13](https://www.debian.org) (LXC template) | Proxmox template mirror | [Various free software licenses (DFSG)](https://www.debian.org/legal/licenses/) |

The exact license of every installed Debian package can be found inside the
container in `/usr/share/doc/<package>/copyright`.

## Trademarks

- **XWiki** is a trademark of XWiki SAS.
- **Proxmox** and **Proxmox VE** are registered trademarks of Proxmox Server
  Solutions GmbH.
- **Debian** is a registered trademark of Software in the Public Interest, Inc.
- **Apache Tomcat** and **Apache** are trademarks of The Apache Software
  Foundation.
- **PostgreSQL** is a registered trademark of the PostgreSQL Community
  Association.
- **MariaDB** is a registered trademark of MariaDB plc / MariaDB Foundation.
- **Java** and **OpenJDK** are trademarks or registered trademarks of Oracle
  and/or its affiliates.

All trademarks are used only to describe what the scripts install
(nominative use). This project is an independent community project and is
**not affiliated with, endorsed by or sponsored by** any of the companies or
organizations named above.
