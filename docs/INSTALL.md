# Install guide

## What you need
- A Kindle Paperwhite 1 (tested: firmware 5.6.1.1, Wi-Fi only). Other Kindles with the same software may work, but are untested.
- A **jailbroken** Kindle with **KUAL** and **FBInk** (`/mnt/us/libkh/bin/fbink`). See [CREDITS](../CREDITS.md) for the guides.
- A USB cable and 2.4 GHz Wi-Fi.

Jailbreaking voids the warranty and can damage the device. You do it at your own risk.

## Steps
1. Connect the Kindle by USB. It shows up as a drive.
2. Copy the folder `extensions/rekindle` into the `extensions` folder on the Kindle. Replace files if asked.
3. Open `extensions/rekindle/rekindle.conf` and set your place: `LATITUDE`, `LONGITUDE`, `PLACE`, `TZ_POSIX`, `TZ_IANA`. The default is Călărași, Romania.
4. Eject the Kindle. Open KUAL > **Ceas și vreme** (Clock and weather).
5. Pick a variant: simple weather or 5-day forecast, in portrait or landscape.
6. To leave, tap the X button, or choose **Revenire la Kindle** in KUAL.

Keep the Kindle on a charger while it runs.

## On-screen buttons
| Button | Action |
|---|---|
| Light bulb | Frontlight menu: Off, Min, Medium, Max |
| Arrows | Flip the screen 180° |
| List | Switch between simple and 5-day view |
| Rectangles | Switch portrait / landscape |
| X | Exit to the Kindle |
| Pin (bottom left) | Choose a city: county first, then town |
| 12h/24h and °C/°F (top right) | Clock and unit switches |
| RO/EN (bottom right) | Change the language |

## Add your own cities
Edit `extensions/rekindle/cities.txt`. One line per place: `county|town|latitude|longitude`. A county of `*` makes it a favorite.

## Troubleshooting
- Log file: `extensions/rekindle/rekindle.log`.
- If the Kindle freezes, hold the power button for about 20 seconds.
