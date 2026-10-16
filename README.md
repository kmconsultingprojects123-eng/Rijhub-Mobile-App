# RijHub mobile app

RijHub connects people in Nigeria with trusted, verified artisans (AC
technicians, electricians, plumbers, mechanics, tailors and more), and helps
artisans find work. It launches in Abuja.

The app is mid-redesign. The redesigned app is the default entry point; the
previous app is kept in `lib/legacy/` for reference until each of its screens
has been rebuilt.

## Run it

```sh
flutter pub get
flutter run                          # the redesigned app
flutter run -t lib/legacy/main.dart  # the previous app, for reference
flutter test                         # tests for the redesign
```

The redesign runs entirely on sample data, so no backend or `.env` setup is
needed.

People explore as guests. The app opens on the home with a welcome sheet
over it: "Explore as a guest" (or closing the sheet) goes in as a client,
"Find work as an artisan" as an artisan, and "Sign in" is for returning
people. Posting a job, quoting, the Bookings and
Messages tabs and the "Sign in" buttons open the sign-in sheet. In it,
803 123 4567 signs in as a client and 805 987 6543 as an artisan, each with
sample bookings and earnings. Any other number creates a new account: it
starts empty, and signing in with that number again finds it. Any code works
except 000000, which simulates a wrong code.

## Where things live

| Path | What it holds |
|---|---|
| `lib/app/` | App setup: router, session and sign-in state, dependency wiring |
| `lib/core/` | The design system: theme tokens, components, formatters |
| `lib/data/` | Models, repository interfaces, and the mock implementations |
| `lib/features/` | Screens, grouped by feature (onboarding, auth, location, home, shell) |
| `lib/legacy/` | The previous app. Not compiled into the redesign; excluded from analysis |
| `docs/design-system.md` | Design principles, tokens and component rules |
| `docs/research/` | UX research behind the redesign: onboarding, both homes, benchmarks of comparable apps |
| `docs/legacy-api-inventory.md` | Every call the old app made to the old backend |
| `docs/legacy/` | The previous team's documentation |

## Backend

The previous backend at rijhub.com is no longer available, and the redesigned
app does not call it. Screens read data through the interfaces in
`lib/data/repositories/`. When the new backend is ready, add API-backed
implementations and switch them on in `lib/app/dependencies.dart`.

## Screenshots and QA

Debug builds can start on any screen in any state. Write
`Documents/dev_launch.json` into the app's container before launching, for
example:

```json
{"route": "/welcome"}
{"route": "/home", "role": "client"}
{"route": "/home", "role": "artisan", "signedIn": true}
{"route": "/home", "role": "client", "signIn": "postJob", "phone": "8031234567", "code": "4829"}
```

See `lib/app/dev_launch.dart` for the options. Release builds ignore it.
