# Borealis Setup Script

Install with one command:

```bash
curl -fsSL https://tinyurl.com/setupborealis | bash
```

or:

```bash
curl -fsSL https://raw.githubusercontent.com/dagahan/networking/main/install.sh | bash
```

After launch:

1. Sign in to Tailscale when prompted.
2. Return to terminal and finish the short setup prompts.
3. Connect using your device name over Tailscale SSH.

Optional flags:

```bash
curl -fsSL https://tinyurl.com/setupborealis | bash -s -- --supermaster-url <url> --role <master|slave> --non-interactive
```
