"""Employi's store listing text, checked against each field's limit.

    python3 listing.py OUT_DIR     # writes App Store and Google Play text files

Every line here was checked against what the app and server do on
24 October 2026 (see SKILL.md, "Claims"). No em dashes, no claim the data
doesn't back: few artisans yet, Abuja only. Voice notes are understood
(Gemini), and the chat reads its messages aloud (build 35 on).
"""
import sys
from pathlib import Path

DESCRIPTION = """Employi (formerly RijHub) connects you with skilled, ID-checked artisans in Abuja: AC technicians, electricians, plumbers, generator repairers, cleaners, carpenters and more.

HOW IT WORKS
1. Say what needs fixing. Type it, record a voice note or snap a photo.
2. See trusted artisans near you, with their prices, work photos and reviews.
3. Pick a time, then book and pay through Employi. Your money is held safely until the job is done.

WHY EMPLOYI
• Every artisan's ID is checked before clients can book them.
• Prices are shown up front, before you book.
• Employi can read every message aloud, for anyone who would rather listen than read.
• Your money is held safely until the job is done. If something goes wrong, our team steps in.
• Chat with your artisan in the app, and follow every step: accepted, on the way, started, done.
• A start code proves your artisan has arrived before the job begins.

FOR ARTISANS
Join free in the chat, with just your phone number and your name. Add your services and prices, check your ID, and get booked by clients near you. When a client confirms a job, we send the money straight to your bank.

Need help? Open Profile, then Help and support."""

WHATS_NEW = """RijHub is now Employi, with a simpler app. Say what needs fixing, typed or as a voice note, and book an ID-checked artisan with the price up front. The app can read every message aloud. Your money is held safely until the job is done. Artisans join in the chat with just a phone number and their name, add their prices, get booked, and get paid straight to their bank."""

APP_STORE = [
    ("App name", 30, "Employi"),
    ("If \"Employi\" is taken, use this name instead", 30, "Employi: Book Artisans"),
    ("Subtitle", 30, "Book ID-checked artisans"),
    ("Promotional text", 170, "Say what needs fixing and book an ID-checked artisan near you, with the price up front. "
                              "Your money is held safely until the job is done."),
    ("Keywords (comma-separated, no space after commas)", 100,
     "RijHub,plumber,electrician,AC repair,handyman,generator,cleaning,carpenter,painter,fumigation,Abuja"),
    ("Description", 4000, DESCRIPTION),
    ("What's New in This Version", 4000, WHATS_NEW),
]

GOOGLE_PLAY = [
    ("App name", 30, "Employi"),
    ("Short description", 80, "Book ID-checked artisans in Abuja. Prices up front. Money held till it's done."),
    ("Full description", 4000, DESCRIPTION),
    ("Release notes (What's new)", 500, WHATS_NEW),
]


def write(path: Path, title: str, fields) -> None:
    out = [title, "=" * len(title), "",
           "Copy each field between its lines. The count is the field's length and the store's limit.", ""]
    for name, limit, text in fields:
        assert len(text) <= limit, f"{name}: {len(text)} > {limit}"
        assert "—" not in text, f"{name}: em dash"
        out += [f"── {name}  ({len(text)} of {limit} characters) " + "─" * 8, text, ""]
    path.write_text("\n".join(out))


if __name__ == "__main__":
    d = Path(sys.argv[1])
    d.mkdir(parents=True, exist_ok=True)
    write(d / "App Store text.txt", "Employi: App Store listing", APP_STORE)
    write(d / "Google Play text.txt", "Employi: Google Play listing", GOOGLE_PLAY)
    for name, limit, text in APP_STORE + GOOGLE_PLAY:
        print(f"{len(text):5} / {limit:<5} {name}")
