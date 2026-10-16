# RijHub design system

The rules behind the redesigned app. Code lives in `lib/core/`. If something
here and the code disagree, fix one of them.

## Principles

1. **Explore first, sign up when it matters.** The app opens on the home,
   with a short welcome sheet over it on first launch ("Explore as a guest"
   is its main button). Nobody is asked for anything until an action needs an account
   (booking, posting a job, quoting); then a short sheet asks for a phone
   number, a code and a name, over the screen they were on.
   No permission prompts up front either: people pick their area from a
   list, and notifications are asked for when they become useful (after a
   booking, or when an artisan first goes available).
2. **What people came for fills the first screen.** Clients see artisans
   (at least four on a 390 x 844 phone); artisans see work (today's jobs,
   requests, new jobs). Headers, search and filters together take no more
   than about a fifth of the screen.
3. **Size follows consequence.** A binary state is a pill in the top bar,
   never a card. A passive number (earnings) is a pill or one row. An
   optional nudge (setup, post a job) is one row of 64pt at most. Only a
   decision with money and a deadline (a direct request) gets a card.
4. **Flat lists.** Feeds are rows at list heights (56 / 72 / 88pt for one,
   two or three lines) with hairline dividers, not stacks of tall cards, and
   a row is one tap target: no repeated buttons down a list.
5. **One job per screen.** Each screen has a single primary action, and it
   is the only crimson fill on it. Everything else is visibly secondary.
6. **Trust is the product.** Verification, ratings, prices and distance are
   shown the same way everywhere, calmly and without hype.
7. **Quiet by default.** No gradients on surfaces, no glow, no shadows on
   cards. Crimson is for actions and the occasional brand moment, not
   decoration.
8. **Local and specific.** Naira, +234 numbers, Abuja neighbourhoods, and the
   trades people here actually hire for (generator, AC, solar).
9. **Light on data and battery.** Bundled fonts and icons, compressed images,
   skeletons instead of spinners, no animation that doesn't explain a change.

## Brand

- **Logo:** `RijHubLogo` (`lib/core/widgets/brand.dart`). Use `color` on light
  backgrounds, `onDark` on photos and dark mode, `white` on crimson. The
  artwork is the original lockup, only cropped. Don't redraw it or drop the
  tagline.
- **Crimson `#A20025`** is the brand colour, unchanged. White text on it is
  8.2:1.
- **Black** (the "HUB" of the logo) is the second brand colour, used for
  high-emphasis cards such as earnings.

## Colour

Always read colours from the theme: `context.colors.<role>`. Never hardcode a
hex value in a screen. Light and dark values are in `app_colors.dart`.

| Role | Use |
|---|---|
| `brand` / `onBrand` | Primary buttons and other filled crimson surfaces with white on them |
| `brandStroke` | Thin crimson lines and small marks: focus borders, carets, selected outlines, progress, ticks, unread dots |
| `brandText` | Links, the active tab and crimson text on the page background |
| `brandSubtle` | Selected cards and chips, initials avatars |
| `background`, `surface` | Page and cards |
| `surfaceMuted` | Inputs, icon tiles, quiet containers |
| `surfaceStrong` / `onSurfaceStrong` | The dark earnings card |
| `border`, `borderStrong` | Hairlines and outlines |
| `inputBorder` | The edge of inputs and code boxes, 3:1 on the page |
| `textPrimary`, `textSecondary`, `textTertiary` | 17.9:1, 7.8:1 and 5.3:1 on white |
| `success`, `warning`, `error`, `info` (+ `…Subtle`) | Status, always with an icon or label |
| `verified` | The verified seal, and nothing else |
| `rating` | Stars |
| `online` | "Available" dots |

Errors use vermilion `#D92D20`, not the brand crimson, so an error never
looks like a call to action.

In dark mode the brand crimson is only about 2:1 on the dark surfaces. It
stays for filled surfaces with white on them (8.2:1), while thin lines and
marks use `brandStroke` (`#D25A75`, 4.3:1 or more) and text uses
`brandText` (`#E595A6`). In light mode `brandStroke` is the brand crimson.
Anything that shows a state, such as a selected chip, also changes shape
(a tick), so the state never rests on colour alone.

## Type

Inter, bundled in `assets/fonts/inter`. Styles live in `AppText`:

| Style | Size / line | Weight | Use |
|---|---|---|---|
| `display` | 32/38 | 700 | Onboarding headlines |
| `headline` | 26/32 | 700 | Screen titles |
| `title` | 20/26 | 700 | Section titles, big numbers |
| `titleSmall` | 16/22 | 600 | Card and list titles |
| `bodyLarge` | 16/24 | 400 | Lead paragraphs, inputs |
| `body` | 15/22 | 400 | Default text |
| `bodySmall` | 13/18 | 400 | Supporting text |
| `label` | 16/20 | 600 | Buttons |
| `labelSmall` | 14/18 | 600 | Links, chips, field labels |
| `caption` | 12/16 | 500 | Metadata, tags, tab labels |

Sentence case everywhere. No all-caps buttons, no letter-spaced labels.

## Sizing with ScreenUtil

Screens are designed on a 390 x 844 frame and scale with the device through
`flutter_screenutil`: `.w` for spacing, sizes and radii, `.sp` for type.
(Radii use `.w` rather than `.r`, which follows the shorter side and would
tighten corners on short phones while spacing stays almost the same.) The
tokens (`AppSpace`, `AppRadius`, `AppSize`, `AppText`) already do
this, so use them rather than raw numbers. They are getters, so expressions
that use them can't be `const`. `RijHubApp` caps the scale at 125% for
tablets. `AppSize.minTapTarget` (48) is never scaled down.

## Space, shape, motion

- **Spacing:** 4-point grid (`AppSpace`). Screen side padding is
  `AppSpace.gutter` (20). Sections are 32 apart; items in a list are 12 apart.
- **Radius:** 12 for buttons, inputs and tiles, 16 for cards, 28 for sheets,
  pill for chips, tags and badges.
- **Height:** primary buttons and inputs are 56. Tap targets are at least 48.
- **Inputs:** a `surfaceMuted` fill with a 1px `inputBorder` edge, so a
  field is easy to find in sunlight; 1.5px `brandStroke` while focused,
  `error` when wrong.
- **Elevation:** cards use a 1px `border`, the tab bar a top border, and
  sheets sit on a scrim. `AppShadows.floating` is for the rare surface that
  floats over content without a scrim, such as a menu.
- **Motion:** 150 ms for presses, 240 ms for state changes, 400 ms for larger
  transitions, using `AppMotion.standard`. Respect reduced motion:
  `context.motion(AppMotion.base)` gives no duration when it is on. Android's
  "Remove animations" and iOS's "Reduce Motion" both turn on
  `MediaQuery.disableAnimations` (`RijHubApp` adds the iOS one), so checking
  it covers both. The exception is `AnimatedSize`, which fails with a zero
  duration; leave it out under reduced motion instead.
- **Focus:** buttons and every `Pressable` take keyboard and switch focus and
  show a ring while focused that way (never on touch). Enter or Space
  activates them.

## Components (`lib/core/widgets`)

| Component | Use it for |
|---|---|
| `AppButton` | Every button. `primary` once per screen; `secondary` for alternatives; `tertiary` for low-emphasis actions; `inverse` on crimson, dark cards or photos. `small` looks 36 tall and pads its touch area to 48. Pass `semanticLabel` when the same label repeats down a list. |
| `AppTextField` | Text inputs with a label above and errors below. Screen readers hear the label as the field's own name; pass `semanticLabel` when there is no visible label (a search field). |
| `PhoneNumberField` | Nigerian phone numbers. Fixed +234, formats as you type. |
| `OtpCodeField` | 6-digit codes, with SMS autofill and paste. One text field for screen readers. |
| `SelectionCard` | Choosing one of a few large options inside a flow. (The welcome screen's role choice uses photo tiles of its own.) |
| `AppChip` | Filters and multi-select. Give chips an icon: a selected chip swaps it for a tick, so its state has a shape as well as a colour. |
| `AppCard` | Any grouped content. Pass `onTap` to make it pressable. |
| `SectionHeader` | A section title with an optional "See all", which takes taps in a 48pt band around the row. The band needs parents that pass taps on: a `Column`, or `SliverList.list` with `addRepaintBoundaries: false`. |
| `AppAvatar` | People. Falls back to initials. |
| `VerifiedBadge`, `RatingLabel`, `StatusTag` | Trust and status signals. Tags are pills. |
| `AppIconButton` | Icon-only actions (back, notifications). |
| `FlowTopBar`, `StepProgress` | Full-screen multi-step flows (posting a job, booking). The sign-in sheet has its own bar, with a close button. |
| `SkeletonBox`, `SkeletonPulse` | Loading placeholders. |
| `EmptyState` | A whole screen with nothing to show yet. |
| `InlineError` | A section that failed to load, with "Try again". |
| `InlineNote` | A short, quiet message inside a section (an empty list). |
| `Pressable` | Making a custom surface tappable with the standard press feel and keyboard focus. Pass `focusRadius` to match the child's corners; its ring sits 3pt outside the edges (`focusOffset: 0` for children with their own touch padding, or in lists that clip). |

Icons are Iconsax (`iconsax_plus`): `IconsaxPlusLinear` by default,
`IconsaxPlusBold` for active and emphasised states. Arrows always use Linear
(`arrow_left`, `arrow_right`, `arrow_right_3` for a chevron, `arrow_down`).
Category icons come from `CategoryIcons.of(key)`. Brand logos are not in
Iconsax: Google uses `GoogleMark`, Apple `Icons.apple`, WhatsApp
`FontAwesomeIcons.whatsapp`.

## Screen anatomy

1. Status bar style set with `AnnotatedRegion` when the top of the screen is
   a photo or crimson.
2. A top row: `FlowTopBar` in full-screen flows, the sheet's own bar in the
   sign-in sheet, or the screen's own header.
3. A title (`headline`), then one line of `body` in `textSecondary` saying
   what to do.
4. Content.
5. The primary action, pinned at the bottom in flows.

## Writing

- Plain, warm and short. Say what happens next ("We'll text you a 6-digit
  code").
- Money as `Naira.format(8000)` → ₦8,000. Ranges as ₦8,000 – ₦12,000.
- Phone numbers as +234 803 123 4567.
- No claims we can't stand behind (for example "3× more bookings").

## Data and state

- Screens read data through repository interfaces
  (`lib/data/repositories`), provided at the root:
  `context.read<ArtisanRepository>()`. They never call HTTP directly.
- Session state is `SessionController` (`isGuest`, `role`, `hasOnboarded`);
  an in-progress sign-in is `AuthFlowController` (both in
  `lib/app/session.dart`).
- To require an account, call
  `context.read<AuthGate>().ensureSignedIn(context, AuthPrompt.postJob)`. It
  returns true straight away for signed-in people and opens the sign-in sheet
  for guests. Pick the prompt for the action (`postJob`, `sendQuote`,
  `bookings`, …). A general way in, which new and returning people both use,
  is `AuthPrompt.join` ("Welcome to RijHub"); keep `AuthPrompt.signIn`
  ("Welcome back") for places where the person has said they have an
  account.
- Navigation uses the paths in `Routes` (`lib/app/routes.dart`).
- Mock data (`lib/data/mock`) stands in for the backend until the new API
  exists; swap implementations in `lib/app/dependencies.dart`. The mocks
  share one record of accounts, told who is signed in by
  `AuthRepository.useAccount`, so the sample accounts keep their bookings
  and earnings and a new account starts empty.
