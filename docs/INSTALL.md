# Install guide

## What you need
- A Kindle Paperwhite 1 (tested: firmware 5.6.1.1, Wi-Fi only). Other Kindles with the same software may work, but are untested.
- A **jailbroken** Kindle with **KUAL** and **FBInk** (`/mnt/us/libkh/bin/fbink`). See [CREDITS](../CREDITS.md) for the guides.
- A USB cable and 2.4 GHz Wi-Fi.

Jailbreaking voids the warranty and can damage the device. You do it at your own risk.

## Steps
1. Download `MeteoAlarmKindle-v2.061.zip` from the [download folder](../download/MeteoAlarmKindle-v2.061.zip?raw=1) and unzip it.
2. Connect the Kindle by USB. It shows up as a drive.
3. Copy the `extensions` folder to the root of the Kindle. Replace files if asked.
4. Optional: open `extensions/meteoalarmkindle/meteoalarmkindle.conf` and set your place (`LATITUDE`, `LONGITUDE`, `PLACE`, `TZ_POSIX`, `TZ_IANA`). The default is Călărași, Romania. You can also pick a city on the screen later.
5. Eject the Kindle. Open KUAL > **Meteo Alarm Kindle**.
6. Pick a variant: simple weather or 5-day list, in portrait or landscape.
7. To leave, tap the X button.

Keep the Kindle on a charger while it runs.

### Upgrading from rekindle or 2.051 and older
The old app lived in `extensions/rekindle`. On its first start, Meteo Alarm Kindle stops the old one and copies your city, °C/°F, 12h/24h and language from it. Then delete `extensions/rekindle` from the Kindle.

## On-screen buttons
| Button | Action |
|---|---|
| ☰ (portrait: top left; landscape: bottom right) | Menu: orientation, view, rotate 180°, refresh weather, °C/°F, 12h/24h, language |
| Light bulb (top right) | Shows the 24-step light bar; swipe on the left edge to change the light |
| X (top right) | Exit to the Kindle |
| Pin (portrait: bottom left; landscape: bottom right) | Choose a city: favourites on top, then county, then town |
| Left edge (dotted) | Swipe up for more light, down for less |

## Add your own cities
Edit `extensions/meteoalarmkindle/cities.txt`. One line per place: `county|town|latitude|longitude`. A county of `*` makes it a starting favourite. After that, the favourites are the last 3 cities you chose.

## Settings
All settings are in `meteoalarmkindle.conf`, with a comment for each: weather and warning intervals, night hours, auto light, light swipe width, pollen, menu and light timeouts.

## Troubleshooting
- Log file: `extensions/meteoalarmkindle/meteoalarmkindle.log`. The first line of each start has the version.
- If the Kindle freezes, hold the power button for about 20 seconds.

## For developers
- `tools/make_ui.py` (Python + Pillow) makes the static images in `ui/`.
- `tools/make_widths.py` makes the glyph width tables in `fonts/`.
- `meteoalarmkindle.sh preview LAYOUT ORIENT [menu|light|pick]` draws a screen from cached data.
