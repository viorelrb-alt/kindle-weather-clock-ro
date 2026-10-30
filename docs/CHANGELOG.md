# Meteo Alarm Kindle: changelog (latest: v2.062)

Weather clock with MeteoAlarm warnings for the Kindle Paperwhite 1: a KUAL extension (shell
script + FBInk). It runs through KUAL (Kindle Unified Application Launcher) and grew out of
rekindle, an earlier clock and weather script.
Weather, UV index, air quality and pollen from Open-Meteo, warnings from MeteoAlarm (ANM, Romania).

## Version

2.062: UV index from the air quality service (humidity without it), moon / pressure / air quality boxes, low-battery light blink and pause. 2.061: portrait no-codes layout side by side, ☰ menu order, fixes from the 2.06 log. 2.06: menus close at once, Kobo-style light bar, battery text fix, version in the log. 2.055: larger box titles, separate boxes, capitals for the info lines, icon fixes. 2.054: no-codes layout, "now" marker, light panel fixes. 2.053: faster city picker, pressed buttons, larger light panel. 2.052: renamed to Meteo Alarm Kindle. 2.051: small design fixes. 2.05: layout fixes after the second Kindle test. 2.04: Back / Close / Next row in the city picker. 2.03: the city picker is a speech bubble. 2.02: fixes from the first test on the Kindle. 2.01 was the first release of the new interface (2.xx).
The 1.xx series is the old interface (last: 1.35).

## What is new in 2.062

- Why the UV box showed "–": the weather model (`MODEL=icon_seamless`, DWD ICON) has no UV
  index, so Open-Meteo returned `uv_index_max: null`. The UV index now comes from the
  Open-Meteo air quality service (CAMS), fetched hourly with pollen, as the index now ("Low"
  under the number for 0-2). It is shown only in the daytime under a clear, mostly clear or
  partly cloudy sky; when overcast, foggy, wet, at night or without UV data the box shows the
  relative humidity (%, level and the same 5-step scale).
- Landscape, simple view: the three boxes at the bottom right take turns every 15 minutes
  (ALT_BOXES=1): Sun / UV index (or Humidity) / Pollen, then Moon / Pressure / AQI.
  Moonrise and moonset are computed on the Kindle (Open-Meteo has no moon data); checked
  against PyEphem within 3 minutes. Pressure is `pressure_msl` in hPa, with the trend over
  about 3 hours once there are readings. AQI is the European air quality index (Good, Fair,
  Moderate, Poor, Very poor, Extremely poor; 6-step scale).
- Low battery: at 21% (not charging) a lit frontlight blinks 4 times at Mediu (2 s off, 2 s
  on), then goes off, and the automatic evening light is paused until the battery is back at
  50%; then, between sunset and 23:00, it comes on again. The pause is kept in `light.pause`
  (survives a restart). Settings: LIGHT_BLINK_AT, LIGHT_BLINK_TIMES, LIGHT_RESUME. BATT_LOW
  (25%) still keeps the evening light off and shows "Charge me".
- Log: `weather:` lines add `hum=` and `press=`; `air: AIR_UV=… AIR_AQI=… POLLEN_LVL=…`
  replaces `pollen:`; also `moon:` and `battery light:`.

## What was new in 2.061

After the test of 2.06 on the Kindle (log of 29 Oct) and the mock-ups checked in Photon:

- Portrait, no warning codes (5-day, rain and simple views): the free area is split in two
  equal halves side by side. The temperature is in the left half and ends on the middle, so
  the room on its left takes the minus in winter; the weather icon is centred in the right
  half. Landscape is unchanged.
- ☰ menu: at each start the order is Orientation, View, Rotate 180°, Refresh weather,
  Temperature, Clock, Language. The first four move like the favourite cities: the last one
  used goes to the top. The language row is in the display language ("Limba: engleză",
  "Language: Romanian").
- Fix: the light pop-up's timer ran out during a long swipe and closed it mid-swipe; a ☰ menu
  opened while the screen was being redrawn then stayed on screen but ignored taps. A swipe
  now renews the timer first, and a redraw draws an open pop-up again instead of dropping it.
- Buttons near an edge of the screen take taps up to that edge (taps at y 752 in landscape
  were lost).
- A failed weather download is tried again after 15 s (up to 3 times in a row), not only at
  the next minute: right after start the Wi-Fi is often not up yet.
- The log names each ☰ menu choice (`menu: Vedere: simplă (v)`).

## What was new in 2.06

After the test of 2.055 on the Kindle (log and photos of 29 Oct):

- Pop-ups (☰ menu, light, city picker) close at once on a tap outside: the screen under them
  is saved from the framebuffer when they open and copied back when they close, with a flash.
  2.055 redrew the whole screen (several seconds), so taps outside seemed to do nothing. The
  touch loop also pauses 0.3 s after a tap instead of 1 s, so fewer taps are lost.
- Light button: the − / + / bar / MIN / MEDIU / MAX panel is gone. The button now shows, over
  the swipe dots on the left edge, a light bar like the Kobo Libra 2's (24 steps, an arrow at
  the current step), and under the button a small bubble with the step and a hint to swipe on
  the left edge. Swiping moves the arrow and the step live. The light button again, a tap
  elsewhere or `LIGHT_SECONDS` (now 10) without a swipe close it and the dots come back.
- Battery: "Încarcă bateria" and "Se încarcă" share one cleared zone (landscape: it now
  reaches the left edge of the right column), shrunk to fit, so no letters of the old message
  stay behind ("ÎncSe încarcă").
- The log's start line has the version: `start v2.06 (simple layout, landscape)`.
- Log of 28-29 Oct checked: one weather fetch and one NTP sync failed (network, both retried
  fine); "can't open …/picker" appeared only with 2.052.

## What was new in 2.055

- Box titles (the gray bands) are larger and heavier (drawn twice, 1 px apart), sized to each
  band and box. Sun, UV index and pollen share one size.
- Landscape: the 3 bottom day boxes (5-day view) and Sun / UV index / Pollen are now 3
  separate boxes each, aligned under the boxes above them.
- Sun and pollen texts are black, like the UV level.
- "RESIMȚIT", "MAX / MIN" and "VÂNT" are in capitals, one size (`TXT_INFO`, 30) on every
  screen, smaller than the weather description. The city has one size (`TXT_CITY`, 36).
- Portrait with codes: the description and the wind go right, under the temperature, as
  without codes. Landscape: the description, then RESIMȚIT, MAX / MIN, VÂNT, then the city.
- The red-code sign is a triangle with a black outline, white inside and a black "!".
- Weather icon: its white square no longer cuts the frame line (landscape, no codes) or the
  warning texts (with codes); a wide "cloudy" icon no longer covers the clock or the digits.

## What was new in 2.054

- No warning codes (portrait and landscape): the "FĂRĂ AVERTIZĂRI METEO" box is gone. The free
  area above the texts is split into two equal halves: the weather icon centred in the upper
  one, the temperature centred in the lower one (mock-ups of 28 Oct). In portrait the
  description and the wind move right, under the temperature; in landscape "Resimțit" is the
  first line under it. With codes the layout is as before.
- Negative temperatures: a short thin minus bar, centred on the height of the digits.
- Precipitation chart: "acum" with a black arrowhead and a dotted line down to the top of the
  bar, placed by the minute within the current hour.
- Light panel: MIN / MEDIU / MAX set the light and close the panel; after − / + or the bar it
  stays `LIGHT_SECONDS` (4) more. A tap on the light, ☰ or city button while its pop-up is open
  is ignored (it used to close it).
- New setting `CLOSE_OUTSIDE` (1): a tap outside an open pop-up closes it; 0 ignores such taps.
- While a pop-up is open the main loop only updates the clock, so a full redraw can no longer
  wipe the pop-up while its state says it is open.

## What was new in 2.053

- City picker: it opened only after several seconds (the whole screen was redrawn under it),
  so a second tap on the city button closed it while it was still being drawn. It is now
  drawn straight over the screen; the county and town rows are images made ahead of time
  (`ui/loc/<md5 of the names>.png`, by `tools/make_ui.py`), and pages whose names changed in
  `cities.txt` are drawn name by name. A tap on the city button while it is open is ignored,
  and taps that come while it is being drawn are not read. The bubble has the same height on
  every page, so turning a page redraws only the bubble.
- Favourites are the last three cities chosen (`recent.sel`): the current one, then the one
  before, then the one before that. They start as the current city and the `*` lines of
  `cities.txt`.
- Every tapped button, menu row, picker name and light preset turns medium gray at once.
- Closing any pop-up (menu, light panel, city picker) redraws the screen with a flash.
- Light panel 20% larger (456 x 228); MIN, MEDIU and MAX boxes as wide as their words.
- Warning codes: yellow light gray; orange and red medium gray; red also gets a black
  triangle with "!" beside the code.
- The log has `picker:` lines (open, close and why, city button ignored).
- Fixed the log error "can't open /tmp/meteoalarmkindle/picker".

## What was new in 2.052

- Renamed: the KUAL entry is "Meteo Alarm Kindle"; the folder is `extensions/meteoalarmkindle`
  (script `bin/meteoalarmkindle.sh`, settings `meteoalarmkindle.conf`, log
  `meteoalarmkindle.log`).
- Upgrading from 2.051 or older: on its first start it stops the old dashboard if it still
  runs and copies the chosen city, °C/°F, 12/24h and language from `extensions/rekindle`.
  Then delete `extensions/rekindle` from the Kindle.

## What was new in 2.051

- Portrait: the first warning box touches the line under the clock, and the line stops just
  before the box's rounded corner.
- Portrait: the last three days are in three separate boxes, like the two above.
- Landscape: the lines between the last three days also cross the gray header.
- Landscape: the weather icon is 3% smaller and kept clear of the "C".

## What was new in 2.05

- Light swipe zone narrowed to 60 px (SWIPE_W, now in screen pixels) and marked with a column
  of gray dots in the left margin, larger toward the top.
- Weather icon centred on the temperature digits (vertically) and in the space to their right,
  using the drawing's own bounds (`icons/centru.txt`, made by `tools/make_ui.py`).
- Warning code bands have rounded ends; more room under them for capitals such as "Â".
  In portrait they start below the line under the clock; in landscape inside the panel.
- Light panel: MIN / MEDIU / MAX only (no "Oprit" button; − or the bar turn the light off).

## What was new in 2.04

- City picker: its own bottom row with Back, Close and Next (2.03 had no way forward from the
  first county tab). The page number (1/2) is in the title.

## What was new in 2.03

- The city picker is a speech bubble over the screen, like the ☰ menu, pointing at the city
  button: no gray buttons, rows of names separated by thin lines, height that follows the
  number of rows. Counties are split into two tabs ("Alba – Gorj", "Harghita – Vrancea").
- Călărași favourite coordinates checked.

## What was new in 2.02

- Fixed the broken top-left corner: text was measured with FBInk, which drew stray glyphs there.
  Text is now measured from glyph width tables (`fonts/*.wid`, made by `tools/make_widths.py`).
  This also fixes warning types cut off at the right edge in portrait.
- Header bands (days, warnings, rain box, sun/UV/pollen) are light gray with black text:
  white text did not show on the Kindle.
- The ☰ menu is a speech bubble pointing at its button, and each row names the choice it
  switches to ("Orientation: portrait" while in landscape). Closing it flashes the screen once
  to clear e-ink ghosting.
- Day temperatures shrink to fit, so "-8° / -15°" stays inside the boxes.
- Current weather: when the model says cloudy or fog but there is precipitation now or this
  hour (or 60%+ chance), it shows drizzle, rain or snow. The log line now has precip, hour_mm
  and hour_pop.
- City picker: "Choose county" title and 86 more towns with coordinates from a checked list (320 in total).

## What was new in 2.01

- Native resolution layout (758x1024 portrait, 1024x758 landscape), with rounded frames.
- Top right: clock and date, then the light button and X (exit).
- One menu (☰) with 7 rows: rotate 180°, view (simple / 5-day list), orientation,
  refresh weather, °C/°F, 24h/12h, Romanian/English. Each row shows the current choice.
- Light panel like the native PW1: − / + (24 steps), tap bar, Off/Min/Mid/Max presets. Closes by itself.
- Kobo-style light swipe on the left edge is kept.
- City shown with county code ("Călărași, CL").
- Up to two MeteoAlarm warnings at once; "FĂRĂ AVERTIZĂRI METEO" when there are none.
- Big temperature with smaller "°" and "C"/"F".
- Precipitation box titled RAIN or SNOW by majority of hours; snow bars dark gray.
- Simple view without precipitation shows 3 day capsules.
- Landscape: SUN / UV / POLLEN box (Open-Meteo air-quality API).

## Install

Copy the `extensions` folder to the Kindle root (Replace). Start from KUAL.
Settings are in `extensions/meteoalarmkindle/meteoalarmkindle.conf` (new: POLLEN, POLLEN_MINUTES, MENU_SECONDS).

## Notes

- `tools/make_ui.py` (Python + Pillow) regenerates the static frame images in `extensions/meteoalarmkindle/ui/`.
- `tools/make_widths.py` (Pillow) regenerates the glyph width tables in `extensions/meteoalarmkindle/fonts/`.
- `meteoalarmkindle.sh preview LAYOUT ORIENT [menu|light|pick|pick2|pick:COUNTY]` draws a screen from cached data.
- 2.01 was tested on a Kindle PW1; 2.02 to 2.062 are tested with PC previews (see `previews/`).

---

## Pe scurt (română)

Aplicația se numește acum Meteo Alarm Kindle (folderul extensions/meteoalarmkindle). Rulează prin KUAL și a pornit de la rekindle. Dacă ai avut o versiune veche, șterge extensions/rekindle de pe Kindle. Copiază folderul `extensions` pe Kindle (Replace) și pornește din KUAL.
Nou în 2.062: UV-ul vine de la serviciul de calitate a aerului (modelul ICON nu are UV, de aceea apărea „–”); fără UV, caseta arată Umiditatea (UV doar ziua, cu Senin / Predominant senin / Parțial noros); în peisaj, vederea simplă, casetele alternează la 15 minute între Soare / UV / Polen și Lună / Presiune / ICA; la 21% lumina clipește de 4 ori, se stinge și aprinderea automată stă pe pauză până la 50%.
Nou în 2.061: în portret, fără coduri, temperatura e în stânga (se termină la mijloc, cu loc pentru minus) și icoana în dreapta; meniul ☰ are ordinea Orientare, Vedere, Întoarce ecranul, Actualizează vremea, Temperatura, Ora, Limba, iar primele 4 se reordonează ca favoritele; rândul de limbă e tradus; meniul nu mai rămâne „mort” după o glisare lungă; butoanele se pot atinge până la marginea ecranului; vremea se reîncearcă după 15 s; jurnalul scrie alegerile din meniu.
Nou în 2.06: meniurile se închid imediat la atingerea din afară; butonul de lumină arată pe marginea stângă o bară ca pe Kobo Libra 2 și o bulă cu indicații (fără −, +, MIN, MEDIU, MAX); mesajele de baterie nu se mai suprapun; jurnalul scrie versiunea la pornire.
Nou în 2.055: titlurile casetelor mai mari și îngroșate; casete separate în peisaj (zilele de jos și Soare / UV / Polen); RESIMȚIT, MAX / MIN și VÂNT cu majuscule, aceeași mărime peste tot; icoana vremii nu mai acoperă linii sau texte; triunghiul de la codul roșu, alb cu contur negru.
Nou în 2.054: fără coduri, icoana sus și temperatura jos, centrate; minus scurt; „acum” pe graficul de ploaie; MIN/MEDIU/MAX închid panoul de lumină; setarea CLOSE_OUTSIDE.
Nou în 2.053: meniul de locații se deschide repede și nu se mai închide la a doua atingere pe pin; favoritele sunt ultimele 3 localități alese; orice buton atins devine gri mediu; meniurile se închid cu flash; panoul de lumină e cu 20% mai mare; codurile portocaliu și roșu au casetă gri mediu, iar roșul are un triunghi cu „!”.
Detalii complete în `extensions/meteoalarmkindle/CITESTE.txt`. Versiunile 2.02–2.062 sunt testate în simulare pe PC.
