# Sing-Box Client (Flutter)

Cross-platform **UI shell** for your SSPanel subscription; the **data plane is sing-box** (not compiled into this repo).

## Do you need sing-box source code?

**No.** Ship official **[sing-box releases](https://github.com/SagerNet/sing-box/releases)** per OS/architecture, or use **libbox** / platform integrations on Android and iOS. Only clone sing-box source if you plan to **patch the core** or build a custom binary.

## Prerequisites

- Flutter SDK (stable), Dart `>=3.3.0`
- **PATH:** add Flutter’s `bin` directory, e.g. `export PATH="$HOME/development/flutter/bin:$PATH"` (this machine’s SDK was cloned to `~/development/flutter`).
- Platform folders are already generated (`flutter create`). To regenerate:  
  `flutter create . --project-name singbox_client --platforms=android,ios,windows,linux,macos,web`

```bash
cd singbox_client
# 推荐：清理缓存后打 macOS Release 并自动打开
./scripts/build_macos_release.sh
```

或手动：

```bash
cd singbox_client
flutter clean && flutter pub get && flutter build macos --release
open build/macos/Build/Products/Release/singbox_client.app
```

## Authentication (SSPanel)

The app talks to the same endpoints as the web UI:

| Action | Method | Path | Body (form) |
|--------|--------|------|----------------|
| Login | POST | `/shouquan/lg` | `email`, `passwd`, optional `code` (2FA), optional `remember_me` |
| Register | POST | `/shouquan/rg` | `name`, `email`, `passwd`, `repasswd`, `wechat`, `imtype`, `code` (invite), optional `emailcode` |
| Send email code | POST | `/shouquan/send` | `email` |
| Logout | GET | `/shouquan/logout` | — |
| Session check | GET | `/user` | Expect **200** when cookies are valid (otherwise **302** to login) |

Implementation layers:

- `lib/core/api/api_paths.dart` — path constants
- `lib/core/di/app_services.dart` — `Dio` + `PersistCookieJar` (session cookies)
- `lib/data/datasources/auth_remote_datasource.dart` — form POST + JSON decode
- `lib/data/repositories/auth_repository.dart` — repository
- `lib/features/auth/` — Riverpod `AuthNotifier`, login / register（网站根地址与账号在同一页）

**Captcha:** If the panel enables Geetest/reCAPTCHA on login or register, browser flows pass extra fields; this client does not yet embed captcha. Use the website or disable captcha for API-style clients in test environments.

## Layout

| Path | Role |
|------|------|
| `lib/core/singbox/` | `SingboxController` + stub (replace with MethodChannel / FFI) |
| `lib/core/subscription/` | HTTP fetch of subscription body (uses a separate `Dio` today; merge with session `Dio` when the subscription URL requires login) |
| `lib/core/config/` | JSON config builder (extend with `vless://` / `hysteria2://` parsers) |
| `lib/features/auth/` | Panel URL, login, register, cookie session |
| `lib/features/home/` | Subscription preview + sing-box stub |

## Next steps (production)

1. **Parse** panel output (Base64 lines → share links) into sing-box `outbounds`.
2. **Embed** sing-box per platform: subprocess on desktop; `VpnService` / Network Extension + libbox on mobile.
3. **Replace** `SingboxStubController` with a real implementation that passes JSON to native code and surfaces state/errors.

## Assets (optional)

Place downloaded binaries under `assets/sing-box/` locally if you bundle them; that path is gitignored by default to avoid large blobs.
