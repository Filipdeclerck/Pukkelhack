# Pukkelhack

Pukkelhack is a small macOS app that checks the official Pukkelpop Meet-up resale page for selected ticket types. It is built for manual ticket buying: it never signs in, reserves a ticket, or completes a purchase.

## Features

- Select Friday, Saturday, Sunday, Combi and VIP tickets independently.
- Includes tickets without camping, Camping CHILL and Camping RELAX.
- Checks every 20 seconds while the app is open.
- Uses a private URL session, cache-busting query parameters and no-cache headers.
- Shows active and expired offers, with a direct **Koop nu** button for active offers.
- Sends a clickable macOS notification when a new matching ticket appears.
- Includes local diagnostic logs with HTTP status, response time and cache headers; use the **Open diagnostische logs** button in the app to inspect them.

## Download

Download the latest macOS app from the [Releases](../../releases) page. Unzip it, drag **Pukkelhack.app** to Applications and open it.

Because this project is not distributed through the Mac App Store or notarised with an Apple Developer ID, macOS may require a one-time Control-click → **Open** confirmation.

## Build from source

Requirements: Xcode Command Line Tools on macOS 13 or later.

The app is an AppKit application defined in `main.swift`. A universal build can be created for Apple Silicon and Intel Macs with `swiftc`, then bundled as `Pukkelhack.app` using the included `Info.plist`.

## Credits

Built with respect for the festival and love for the music by Fillter | Filip De Clerck.

## Friendly note

Pukkelhack is an independent, unofficial hobby project and is not connected to Pukkelpop or the festival organisation in any way. It is not intended to get in the festival's way; it simply helps people with busy days spend less time manually checking the official Meet-up page.

Pukkelhack never guarantees a ticket. We hope it helps you check at the right moment, though — and if it helps you secure one, have a wonderful and joyful festival! 🎉

© 2026 All rights reserved.
