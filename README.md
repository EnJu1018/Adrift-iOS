# Adrift iOS

這是 Adrift 的原生 iOS App，使用 SwiftUI 開發，資料來源共用 Adrift 後端 API。這不是 WebView wrapper，也不建立第二套後端或資料庫。

本專案獨立維護於 [EnJu1018/Adrift-iOS](https://github.com/EnJu1018/Adrift-iOS)。網站與 API 維護於 [EnJu1018/Adrift](https://github.com/EnJu1018/Adrift)，不需要將該 repository 放在本機才能編譯 App。

## Stack

- SwiftUI
- iOS 18+
- Apple Human Interface Guidelines
- Native `NavigationStack`, `TabView`, `List`, `Form`, `Section`, `Sheet`, `Toolbar`
- Conditional iOS 26 Liquid Glass (`glassEffect`, `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`)
- MVVM
- URLSession
- Keychain JWT storage
- MapKit
- CoreLocation
- PhotosPicker
- AsyncImage
- SF Symbols

Minimum iOS Version: iOS 18.0.

Recommended: iOS 26 or later for Liquid Glass effects.

Liquid Glass:

- iOS 26 or later: uses native Liquid Glass APIs.
- iOS 18-25: falls back to SwiftUI Material effects.

## App Icon and Launch

- The production icon is stored in `Adrift/Assets.xcassets/AppIcon.appiconset`.
- The icon catalog provides Any, Dark, and Tinted appearances for iOS 18 and later.
- The native launch screen uses an adaptive asset color and the centered `AdriftLaunchLogo`.
- Launch and Splash backgrounds automatically follow the system Light or Dark appearance.
- `SplashView` remains visible for at least 0.9 seconds while the existing Keychain JWT and current-user bootstrap finishes.
- The root launch state prevents the login or main screen from appearing before authentication has been resolved.

## Automatic Refresh

- Global refresh buttons are removed from Map, Friends, and Settings.
- Map, Explore, friends, and current-user data refresh automatically on first load, page entry, foreground activation, and a 30-second foreground interval.
- Refreshes are throttled and deduplicated by `AppRefreshManager`.
- Friends keeps native pull-to-refresh for an explicit page-level refresh.
- Subsequent refreshes preserve existing content without showing full-screen loading states.
- Diary and friendship mutations update shared state after server success. Forced refreshes queue behind an in-flight refresh, and older responses cannot overwrite newer diary mutations.
- This is bounded polling, not instantaneous server push. Background polling stops; returning to the foreground refreshes eligible scopes.

Shared Liquid Glass helpers live in:

`Adrift/Components/GlassComponents.swift`

They include `GlassCard`, `GlassPanel`, `GlassFloatingButton`, `GlassToolbarButton`, `GlassProminentButton`, and `GlassChip`. All iOS 26-only Liquid Glass APIs are wrapped inside these components with iOS 18-25 material fallbacks.

## Design System

The shared Adrift iOS design layer lives in:

- `Adrift/Design/AdriftColors.swift`
- `Adrift/Design/AdriftTypography.swift`
- `Adrift/Design/AdriftSpacing.swift`
- `Adrift/Design/AdriftMotion.swift`
- `Adrift/Design/AdriftBackground.swift`

It provides brand colors, mood colors, typography, spacing, motion presets, and the animated Adrift background with abstract map lines and memory lights.

## Backend

The app uses the existing Adrift API. It does not create a new backend, database, or WebView wrapper.

Default API base URL:

```swift
// Adrift/Config/APIConfig.swift
static let baseURL = URL(string: "https://adrifttw.com/api")!
```

`Adrift/Config/APIConfig.swift` is the client-only endpoint configuration. The production URL includes the deployed Nginx `/api` prefix. It is public configuration, not a secret. Keep the production HTTPS default; localhost is not a production endpoint. No Gemini key, JWT signing secret or MongoDB credential belongs in this app. Authentication tokens remain in Keychain.

See [docs/API_CONTRACT.md](docs/API_CONTRACT.md) for the shared API boundary and compatibility checks.

## Implemented Endpoints

- `POST /auth/login`
- `POST /auth/register`
- `GET /users/me`
- `GET /diaries`
- `POST /diaries`
- `GET /diaries/:id`
- `PATCH /diaries/:id`
- `DELETE /diaries/:id`
- `GET /diaries/explore?lat=...&lng=...&radius=...`
- `GET /friends`
- `GET /friends/requests`
- `GET /friends/requests/sent`
- `GET /users/search?userCode=...`
- `POST /friends/request`
- `POST /friends/requests/:requestId/accept`
- `POST /friends/requests/:requestId/reject`
- `DELETE /friends/requests/:requestId/cancel`
- `DELETE /friends/:friendId`
- `GET /ai/life-map`
- `PATCH /users/me/avatar`
- `DELETE /users/me/avatar`
- `PATCH /users/me/name`
- `PATCH /users/me/email`
- `PATCH /users/me/password`

## Parity and Verification

See [SYNC_CHECKLIST.md](SYNC_CHECKLIST.md) for the Web baseline, actual API JSON contracts, implementation status, and live-account acceptance checklist.

Run isolated API and refresh checks on macOS with Xcode installed:

```sh
bash Tests/run-contract-checks.sh
```

These checks compile the actual services/models, intercept requests with URLProtocol, and use an isolated temporary Keychain service. They do not access the backend or replace App data. Live cross-platform verification still requires real test accounts.

## Build

```sh
xcodebuild -project Adrift.xcodeproj \
  -scheme Adrift \
  -destination 'generic/platform=iOS Simulator' \
  build
```

Or open `Adrift.xcodeproj` in Xcode and run the `Adrift` scheme. The shared scheme and embedded workspace are included. There are no external package, CocoaPods or monorepo build dependencies.

For a signing-independent Simulator build:

```sh
xcodebuild -project Adrift.xcodeproj -scheme Adrift \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/adrift-ios-build CODE_SIGNING_ALLOWED=NO build
```

## Independent Development and Release

Clone this repository, open the Xcode project and commit/push here, independently of the website. The default branch is `main`. The bundle identifier remains `com.arren1088.Adrift`; automatic signing uses the existing team `UPLAC3P26S`. A device run or App Store archive requires access to that Apple Developer team and local signing credentials. Do not commit certificates or provisioning profiles.

Select a physical-device destination, update the app version/build when releasing, then use Product > Archive and Organizer in Xcode. App releases do not rebuild or deploy the API. Coordinate API changes in the web repository and preserve backward compatibility for already-installed clients.

## TODO

- Add avatar crop, zoom, and positioning controls after the first PhotosPicker upload flow.
- Add Web features outside this core sync: reactions, historical memories, friend recommendations, and administrative tools as needed.
- Add backend pagination before displaying complete diary histories (the shared list currently caps at 200).
- Add UI tests after backend test fixtures are available.
