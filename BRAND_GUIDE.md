# RIJHUB - Brand Guide

## 1. Brand Overview

**Rijhub** is a Flutter mobile application that connects skilled artisans with customers in need of services. The platform operates on both iOS and Android, supporting two main user roles: **Artisans** (service providers) and **Customers** (service seekers).

---

## 2. Brand Colors

### Primary Color Palette

| Color Name | Hex Code | RGB | Use Case |
|------------|----------|-----|----------|
| **Primary Red** | `#A20025` | RGB(162, 0, 37) | Primary action buttons, links, brand accent |
| **Secondary Red** | `#A20025` | RGB(162, 0, 37) | Consistent with primary (brand reinforcement) |
| **Tertiary Orange** | `#EE8B60` | RGB(238, 139, 96) | Secondary accent, complementary highlights |

### Semantic Colors

| Color | Hex Code | Purpose |
|-------|----------|---------|
| **Success** | `#249689` | Success states, confirmations |
| **Warning** | `#F9CF58` | Warning messages, alerts |
| **Error** | `#FF5963` | Error states, destructive actions |
| **Info** | `#FFFFFF` | Informational messages |

### Light Mode Theme

| Element | Hex Code | Purpose |
|---------|----------|---------|
| Primary Text | `#1A1A1A` | Main content, headings |
| Secondary Text | `#57636C` | Supporting text, labels |
| Primary Background | `#F7F7F7` | Page backgrounds |
| Secondary Background | `#FFFFFF` | Cards, containers |
| Alternate | `#E0E3E7` | Dividers, borders |
| Accent 1 | `#4CA20025` | Subtle primary tint |
| Accent 2 | `#4DA20025` | Subtle primary tint variant |
| Accent 3 | `#4DEE8B60` | Subtle tertiary tint |
| Accent 4 | `#CCFFFFFF` | Light overlay |
| Highlight | `#33A20025` | Highlighted elements |
| Highlight 1 | `#FFFB5C6` | Special highlights |
| Custom Color 1 | `#3FA20025` | Custom brand tint |

### Dark Mode Theme

| Element | Hex Code | Purpose |
|---------|----------|---------|
| Primary Text | `#FFFFFF` | Main content on dark backgrounds |
| Secondary Text | `#95A1AC` | Supporting text in dark mode |
| Primary Background | `#1D2428` | Dark page backgrounds |
| Secondary Background | `#14181B` | Dark cards, containers |
| Alternate | `#262D34` | Dark mode dividers |
| Accent 1 | `#4CA20025` | Dark mode primary tint |
| Accent 2 | `#4DA20025` | Dark mode primary tint variant |
| Accent 3 | `#4DEE8B60` | Dark mode tertiary tint |
| Accent 4 | `#B2262D34` | Dark overlay |
| Highlight | `#1FA20025` | Dark mode highlight |
| Highlight 1 | `#33A20025` | Dark mode special highlight |
| Custom Color 1 | `#FFF298B3` | Dark mode custom brand tint |

### Color Usage Guidelines

- **Primary Red (#A20025)**: Use for main CTAs, primary buttons, important links, and brand identity elements
- **Tertiary Orange (#EE8B60)**: Use sparingly as a complementary accent to add visual interest
- **Text Colors**: Always ensure sufficient contrast for accessibility (WCAG AA minimum 4.5:1 for body text)
- **Dark Mode**: Automatically applied based on system settings; colors are optimized for dark backgrounds

---

## 3. Typography

### Font Families

- **Headings**: Inter Tight (from Google Fonts)
- **Body Text**: Inter (from Google Fonts)
- **Default**: Both fonts are loaded via `google_fonts` package

### Type Scale

| Style | Font | Weight | Size | Usage |
|-------|------|--------|------|-------|
| **Display Large** | Inter Tight | 600 | 64px | Rarely used, maximum emphasis |
| **Display Medium** | Inter Tight | 600 | 44px | Hero sections, page titles |
| **Display Small** | Inter Tight | 600 | 36px | Section headers |
| **Headline Large** | Inter Tight | 600 | 32px | Major headings |
| **Headline Medium** | Inter Tight | 600 | 28px | Section headings |
| **Headline Small** | Inter Tight | 600 | 24px | Subsection headings |
| **Title Large** | Inter Tight | 600 | 20px | Card titles, form headers |
| **Title Medium** | Inter Tight | 600 | 18px | Dialog titles |
| **Title Small** | Inter Tight | 600 | 16px | List item headers |
| **Label Large** | Inter | Regular | 16px | Button text, labels |
| **Label Medium** | Inter | Regular | 14px | Form labels, captions |
| **Label Small** | Inter | Regular | 12px | Small text, hints |
| **Body Large** | Inter | Regular | 16px | Primary body text |
| **Body Medium** | Inter | Regular | 14px | Standard body text |
| **Body Small** | Inter | Regular | 12px | Secondary body text |

---

## 4. Logo & Branding Assets

### Logo Files
Located in `/assets/images/`:
- `app_logo_RH.jpg` - Main app logo
- `logo_black.png` - Black version for light backgrounds
- `logo_white.png` - White version for dark backgrounds
- `app_launcher_icon.png` - App store icon
- `adaptive_foreground_icon.jpg` - Adaptive icon for modern Android

### Logo Usage
- Use full logo on marketing materials and app splash screens
- Use icon-only version for app launcher and small spaces
- Maintain minimum clear space around logo (at least 8dp)
- Never compress, distort, or alter logo proportions
- Always use color or grayscale versions; avoid recoloring

---

## 5. Visual Elements & Components

### Button Styles

#### Primary Button
- **Background**: Primary Red (#A20025)
- **Text Color**: White (#FFFFFF)
- **Padding**: 16px vertical, 24px horizontal
- **Border Radius**: 12px
- **Elevation**: 2px
- **State**: Disabled state uses gray background (#E0E3E7 in light, #262D34 in dark)

#### Secondary Button
- **Background**: Transparent
- **Border**: 1px Primary Red (#A20025)
- **Text Color**: Primary Red (#A20025)
- **Padding**: 12px vertical, 16px horizontal
- **Border Radius**: 12px

#### Text Button (Link)
- **Background**: Transparent
- **Text Color**: Primary Red (#A20025)
- **No padding/minimal styling**
- **Used for secondary actions**

### Input Fields

- **Background Color**: Light mode: #F7F7F7, Dark mode: #1D2428
- **Border**: 1px, color #E0E3E7 (light) or #262D34 (dark)
- **Border Radius**: 12px
- **Focused Border**: 1.5px Primary Red (#A20025)
- **Text Color**: Primary text color
- **Placeholder**: Secondary text color with reduced opacity
- **Padding**: 12px horizontal, 14px vertical

### Cards & Containers

- **Border Radius**: 12px to 16px
- **Shadow**: Subtle shadow (0-4px blur, 0-2px spread)
- **Padding**: 16px to 24px depending on content
- **Background**: Secondary background color

### Icons

- **Size Scales**: 24px (default), 32px (large), 48px (extra-large), 16px (small)
- **Color**: Inherit from theme (primary text or primary brand color)
- **Font**: Font Awesome Flutter (`font_awesome_flutter` package)
- **Material Icons**: Standard Flutter Material icons for common actions

---

## 6. Spacing & Layout

### Spacing Scale

| Size | Pixels | Usage |
|------|--------|-------|
| xs | 4px | Micro spacing |
| sm | 8px | Small gaps |
| md | 12px | Default spacing |
| lg | 16px | Standard spacing |
| xl | 20px | Large spacing |
| 2xl | 24px | Extra large spacing |
| 3xl | 32px | Section spacing |
| 4xl | 40px | Major sections |

### Padding & Margins

- **Page/Screen Padding**: 24px horizontal, 12-32px vertical
- **Section Padding**: 16-24px
- **Card Padding**: 16px minimum
- **List Item Padding**: 12px vertical, 16px horizontal

### Grid System

- **Breakpoints**: Mobile (320px-599px), Tablet (600px+)
- **Standard page padding**: 24px on mobile, 32px on tablet
- **Content max-width**: Flexible, with side padding maintained

---

## 7. Elevation & Shadows

### Shadow Depths

| Level | Blur | Spread | Opacity | Usage |
|-------|------|--------|---------|-------|
| **1** | 2px | -1px | 12% | Subtle elevation |
| **2** | 4px | -2px | 16% | Default elevation |
| **3** | 8px | -4px | 20% | Cards, modals |
| **4** | 16px | -8px | 24% | Floating buttons, top modals |

---

## 8. Animation & Motion

### Durations

- **Quick**: 150ms - Hover states, small transitions
- **Standard**: 300ms - Normal transitions, interactions
- **Slow**: 500ms - Page transitions, major animations
- **Slowest**: 1000ms+ - Welcome screens, splash animations

### Easing

- **Ease In**: Quick start, slower end
- **Ease Out**: Slower start, quick end
- **Ease In-Out**: Smooth, natural motion
- **Linear**: Used for continuous animations

### Examples from Codebase

- **OTP Input Auto-Focus**: Smooth transition to next field (150ms)
- **Countdown Timer**: Updates every 1 second
- **Bottom Sheet**: Slide-up animation (300ms)
- **Button Loading**: Smooth spinner transition (200ms)

---

## 9. Components & Patterns

### Top Navigation Bar

- **Height**: 56px
- **Background**: Secondary background color
- **Shadow**: 1-2px elevation
- **Back Button**: 40px circle, icon centered
- **Status Bar**: Adaptive based on system theme

### Bottom Sheet

- **Border Radius**: 30px top corners
- **Background**: Secondary background color (light/dark aware)
- **Min Height**: 75% of screen
- **Padding**: 24px horizontal, 32px top/bottom
- **Draggable**: When needed (set `enableDrag: true`)

### OTP Input

- **Field Size**: 48x56px each
- **Number of Fields**: 6 digits
- **Border Radius**: 12px
- **Background**: Input field color (light/dark aware)
- **Focused Border**: 1.5px Primary Red (#A20025)
- **Font Size**: 20px, weight 600
- **Auto-focus**: Next field after digit entry
- **Paste Support**: Distributes pasted OTP across fields

### Service Pill / Badge

- **Style**: Rounded chip/badge format
- **Background**: Accent color with reduced opacity
- **Text**: Primary red color
- **Padding**: 6-8px vertical, 12-16px horizontal
- **Border Radius**: 20px (pill shape)

### Feature Item (Grid)

- **Layout**: Horizontal flex row
- **Icon Size**: 24px
- **Label Size**: 12px, weight 500
- **Spacing**: 4px between icon and label

---

## 10. Accessibility Standards

### Color Contrast

- **Normal Text**: Minimum 4.5:1 contrast ratio (WCAG AA)
- **Large Text** (18px+): Minimum 3:1 contrast ratio
- **Graphics/UI Components**: Minimum 3:1 contrast ratio

### Typography

- **Minimum Font Size**: 12px for body text
- **Line Height**: 1.5 for body text, 1.25 for headings
- **Letter Spacing**: Normal for readability

### Interactive Elements

- **Minimum Touch Target**: 48px x 48px
- **Keyboard Navigation**: Fully keyboard accessible
- **Focus Indicators**: Visible focus state on all interactive elements
- **Screen Reader Support**: Semantic HTML/widget structure

### Dark Mode

- Automatically switches based on system settings
- All colors optimized for both light and dark backgrounds
- Sufficient contrast maintained in both themes

---

## 11. App Flow & User Experience

### User Roles

1. **Artisan** (Service Provider)
   - Primary Dashboard: Job requests and service management
   - Profile: Service offerings and ratings
   - Navigation: Home, Search, Bookings, Chat, Profile

2. **Customer** (Service Seeker)
   - Primary Dashboard: Browse artisans and services
   - Search: Find specific services by category
   - Navigation: Home, Search, Discover, Bookings, Profile

### Key User Journeys

#### Registration & OTP Verification
- Splash → Registration Form → OTP Verification → Welcome Sheet → Dashboard

#### Service Booking
- Browse Services → Artisan Profile → Service Details → Booking Sheet → Confirmation

#### Real-time Messaging
- Dashboard → Chat Icon → Conversation → Message Exchange → Notifications

---

## 12. Theme Implementation Details

### Light Mode (Default)
```dart
Primary: #A20025 (Red)
Background: #F7F7F7 (Light Gray)
Surface: #FFFFFF (White)
Text: #1A1A1A (Dark Gray)
```

### Dark Mode
```dart
Primary: #A20025 (Red - consistent)
Background: #1D2428 (Dark Gray)
Surface: #14181B (Darker Gray)
Text: #FFFFFF (White)
```

### Dynamic Theme Switching
- Automatic based on system theme preference
- Manual override available in user settings
- Theme state persisted in SharedPreferences
- FlutterFlowTheme.of(context) provides access to current theme

---

## 13. Firebase Integration & Branding

### Authentication Methods
- **Email/Password**: Primary method
- **Google Sign-In**: Secondary method (with Google logo)
- **Apple Sign-In**: iOS-specific method (with Apple logo)
- **Phone/OTP**: SMS-based verification

### Messaging & Notifications
- **FCM (Firebase Cloud Messaging)**: Push notifications
- **Awesome Notifications**: Local and remote notifications
- **Real-time Updates**: Firestore listeners for live data

### Brand Consistency
- All auth screens follow primary color scheme
- Notification badges use brand colors
- Loading states show primary brand spinner

---

## 14. Payment Integration

### Supported Payment Methods
- **Paystack**: Primary payment gateway
- **Verve**: Alternative payment option (Verve_Logo.svg)
- **Mastercard**: Accepted payment method

### Logo Placement
- Payment gateway logos displayed on checkout
- Always with proper spacing and clear separation
- Never modify or recolor third-party payment logos

---

## 15. Design Specifications Summary

| Aspect | Specification |
|--------|---------------|
| **Primary Color** | #A20025 (Bright Red) |
| **Accent Color** | #EE8B60 (Orange) |
| **Typography** | Inter (body), Inter Tight (headings) |
| **Border Radius** | 12px (default), 16px (large), 20px (pills) |
| **Shadows** | Subtle, 2-4px blur |
| **Dark Mode** | Supported, system-aware |
| **Spacing Unit** | 4px, 8px, 12px, 16px, 20px, 24px |
| **Min Touch Target** | 48x48px |
| **Animation Speed** | 150-300ms standard |
| **Status Bar** | Adaptive (dark/light) |

---

## 16. Implementation Guidelines

### For Developers

1. **Theme Access**: Always use `FlutterFlowTheme.of(context)` for colors
2. **Responsive Design**: Use MediaQuery and LayoutBuilder for responsive layouts
3. **Dark Mode**: Test both light and dark themes during development
4. **Consistency**: Reuse theme values, avoid hardcoded colors
5. **Spacing**: Use consistent spacing scale (4px-based system)
6. **Accessibility**: Follow WCAG 2.1 AA standards

### For Designers

1. **Use Brand Colors**: Always use hex codes from this guide
2. **Typography**: Stick to Inter and Inter Tight fonts
3. **Component Consistency**: Refer to Flutter Material Design guidelines
4. **Spacing**: Maintain 4px-based spacing grid
5. **Dark Mode**: Design for both light and dark themes
6. **High Contrast**: Ensure 4.5:1 contrast ratio for text

---

## 17. Questions & Support

For brand-related questions or updates to this guide:
- Review the `flutter_flow_theme.dart` file for implementation details
- Check `main.dart` for theme initialization
- Refer to specific page implementations for component usage examples
- Update this guide when brand colors, fonts, or design patterns change

---

**Last Updated**: March 2026  
**Version**: 1.0  
**Status**: Active

