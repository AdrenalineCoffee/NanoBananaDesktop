# NanoBananaDesktop

Native macOS desktop app for image generation and image-based prompt workflows using Google Gemini image-capable models, with proxy-aware networking and local history.

## Requirements
- macOS 13+
- Xcode (for app build/run)
- Swift 6 toolchain (`swift test`)
- Gemini API key

## Build and run

### Swift Package (developer mode)
```bash
swift run NanoBananaDesktop
```

### Xcode
1. Open `NanoBananaDesktop/NanoBananaDesktop.xcodeproj`
2. Select target `NanoBananaDesktop`
3. Build and run (`Cmd+R`)

## Tests
```bash
swift test
```

## Runtime data (local, not in repo)
Application config and history are stored in:

`~/Library/Application Support/NanoBananaDesktop/`

Files:
- `config.json` (includes API key / proxy settings)
- `history.json`

These files are intentionally excluded from git.

## Security and secrets
- Never commit API keys, proxy passwords, `.env` files, certificates, or private keys.
- `pre-commit` + CI release-guard checks enforce this repository policy.
- See `SECURITY.md` for vulnerability reporting and disclosure.

## Repository hygiene
This repository excludes:
- local build artifacts (`.build`, `.xcodebuild`, `.app`)
- local user state (`xcuserdata`, `.DS_Store`)
- local logs and temporary files

See `.gitignore` and `scripts/release_guard.sh` for enforced rules.

## License
MIT — see `LICENSE`.
