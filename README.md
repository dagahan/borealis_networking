# Nikita Networking Installer (Public)

Public bootstrap for enrolling Unix devices into Nikita Home Networking.

## Install
```bash
curl -fsSL https://raw.githubusercontent.com/dagahan/networking/main/install.sh | bash
```

## Optional env vars
- `NETWORKING_SUPERMASTER_URL` (required unless entered interactively)
- `NETWORKING_API_TOKEN` (required unless entered interactively)
- `NETWORKING_ROLE_REQUEST` (`master` or `slave`, default: `slave`)
- `NETWORKING_NONINTERACTIVE` (`1` to skip some prompts)

## What it does
1. Detects Linux (apt/pacman) or macOS.
2. Installs bootstrap dependencies (`curl`, `jq`, `sshfs`, etc.).
3. Installs and starts Tailscale.
4. Runs `tailscale up --ssh` (interactive Tailscale auth).
5. Calls super-master enrollment APIs.
6. Sets up local shared FS directory and generated SSH aliases.

## Security boundary
This repo intentionally contains only installer/bootstrap code.
No private orchestration logic, daemon policy, or server secrets are stored here.
