# Shared Backend Contract

The native app and website use the same HTTPS API at `https://adrifttw.com/api`.
The API is owned by [EnJu1018/Adrift](https://github.com/EnJu1018/Adrift), deployed
independently on the existing VPS and backed by the existing MongoDB Atlas.
This repository contains client code only, with no database connection or backend secrets.

## Client Configuration

- Endpoint: `Adrift/Config/APIConfig.swift`.
- Requests: `Adrift/Services/APIClient.swift`, URLSession with Bearer authentication.
- JWT storage: `Adrift/Stores/TokenStore.swift`, existing Keychain service/account.
- Identity: `com.arren1088.Adrift`; changing repository does not change app identity.
- Maps: native MapKit and CoreLocation; no Mapbox SDK or Mapbox token is used.
- Intelligence: calls `GET /ai/life-map`; Gemini credentials remain server-side.

## Existing Routes

Paths below are relative to the configured `/api` base. Responses use
`{ success, message, data }`; authentication data contains `{ token, user }`.

| Service | Routes |
| --- | --- |
| Auth | `POST /auth/login`, `POST /auth/register`, `GET /users/me` |
| Diaries | `GET/POST /diaries`, `GET/PATCH/DELETE /diaries/:id`, `GET /diaries/explore` |
| Friends | `GET /friends`, `GET /friends/requests`, `GET /friends/requests/sent`, `POST /friends/request` |
| Friend actions | `POST /friends/requests/:id/accept`, `POST /friends/requests/:id/reject`, `DELETE /friends/requests/:id/cancel`, `DELETE /friends/:id` |
| Profile | `PATCH /users/me/name`, `/email`, `/password`, `PATCH/DELETE /users/me/avatar` |
| Intelligence | `GET /ai/life-map` |

Diary coordinates are GeoJSON longitude/latitude pairs. Creation sends lat/lng;
editing retains original coordinates and follows server time/location permissions.
Visibility and JWT authorization are always enforced by the backend. Multipart
diary photographs are limited to 5 MiB; avatar uploads to 10 MiB. Relative image
paths use the existing `/api/uploads` mapping.

The current native app does not implement the web Feed or Notifications UI.
Repository separation preserves this baseline; it does not claim new feature parity.
See `SYNC_CHECKLIST.md` for the existing feature gaps and live-account checklist.

## Compatibility and Verification

Run `bash Tests/run-contract-checks.sh` before changing client models or requests.
These checks compile the real services, use URLProtocol fixtures and a temporary
Keychain namespace, and never create production accounts or write production data.

Backend changes must preserve paths, response envelopes, visibility rules and
supported fields for installed iOS clients. Prefer additive fields; coordinate
breaking changes across repositories before release. New backend features do not
automatically imply iOS support. Live authenticated acceptance testing requires
dedicated test accounts and must not use destructive production fixtures.
