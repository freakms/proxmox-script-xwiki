# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-10

### Added
- `xwiki-lxc.sh`: creates a Debian 13 LXC container on Proxmox VE 8/9
  (unprivileged, nesting enabled, start on boot) and runs the installer.
- `install/xwiki-install.sh`: installs XWiki from the official XWiki APT
  repository (`stable` or `lts`) with Tomcat 10 and PostgreSQL or MariaDB,
  sets the Tomcat heap size and waits for XWiki to come up.
- Interactive prompts and unattended mode (`--yes` + environment variables).
- MIT license, third-party notices, ShellCheck CI workflow.
