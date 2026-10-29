#!/bin/sh
# Meteo Alarm Kindle: always-on time & weather dashboard for a jailbroken Kindle, started
# from KUAL. Grew out of rekindle (an earlier dashboard script).
# Target: Kindle Paperwhite 1, FW 5.6.x, BusyBox 1.17 ash, FBInk in /usr/bin.
#
# Usage: meteoalarmkindle.sh start [simple|weather] [portrait|landscape] | stop | status | run [...] | fetch
#   start   launch the dashboard in the background (used by KUAL); the view is the current
#           weather with an hourly precipitation chart when some is due, else the next three
#           days (simple, default), or with the next five days (weather)
#   stop    stop it and bring the normal Kindle UI back
#   status  print whether it is running (and its layout) and the last weather data
#   run     run the dashboard loop in the foreground
#   fetch   fetch weather once and print the parsed values
#   preview draw one screen from the saved data and exit (testing)
#
# While running, pressing the power button exits back to the Kindle UI.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin:/mnt/us/libkh/bin
VERSION=2.061

DIR=$(cd "$(dirname "$0")/.." && pwd)
. "$DIR/meteoalarmkindle.conf"
LANDSCAPE_ROTA=${LANDSCAPE_ROTA:-2}
LIGHT_1=${LIGHT_1:-4}
LIGHT_2=${LIGHT_2:-10}
LIGHT_3=${LIGHT_3:-24}
export TZ="$TZ_POSIX"

STATE=/tmp/meteoalarmkindle
PIDFILE=$STATE/pid
WEATHER_ENV=$STATE/weather.env
LAYOUT_FILE=$STATE/layout
LOG=$DIR/meteoalarmkindle.log

# Liberation Sans, shipped in fonts/ with a glyph width table each (*.wid, made by
# tools/make_widths.py), so text is measured without asking FBInk.
F_BOLD=$DIR/fonts/LiberationSans-Bold.ttf
# One size on every screen: "RESIMȚIT", max / min and wind (regular, capitals, smaller than
# the weather description); the city (bold).
TXT_INFO=30 TXT_CITY=36
F_REG=$DIR/fonts/LiberationSans-Regular.ttf
F_MED=$F_BOLD

log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"
}

trim_log() {
	[ -f "$LOG" ] || return 0
	if [ "$(wc -c <"$LOG")" -gt 200000 ]; then
		tail -n 500 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
	fi
}

# UI language (ro or en), kept in lang.sel. load_lang loads the texts of the language.
LANG_SEL=$DIR/lang.sel

load_lang() {
	l=${REKINDLE_LANG:-$(cat "$LANG_SEL" 2>/dev/null)}
	if [ "$l" = en ]; then
		UI_LANG=en
		T_UNTIL=until T_NOW=now T_RAIN=Rain T_RAINFROM="Rain from" T_MAX=max
		T_SNOW=Snow T_SNOWFROM="Snow from" T_RAINW=Raining T_SNOWW=Snowing
		T_UPDATED=updated T_NODATA="no data since" T_LOADING="Loading weather…"
		T_UPDATING="updating…" T_RETURN="Returning to Kindle…"
		T_LIGHTT=LIGHT T_LIGHTOFF="LIGHT OFF" T_LIGHTH1="Swipe up or down" T_LIGHTH2="on the left edge of the screen." T_PICK="Choose county" T_PICKTOWN="choose town"
		T_BACK=Back T_PAGE=Page T_CLOSE=Close T_NEXT=Next
		T_FEELS="Feels like" T_WIND=Wind T_HI=High T_LO=Low T_CHARGING=Charging T_CHARGEME="Charge me"
		T_WARN="YELLOW ORANGE RED" T_WARNCODE=WARNING T_NOWARN="NO WEATHER WARNINGS"
		T_DAY1=TOMORROW T_DAY2="DAY AFTER" T_NEXT12="NEXT 12 HOURS" T_NOWMARK=now T_RAINUP=RAIN T_SNOWUP=SNOW
		T_LEGSNOW=snow T_LEGRAIN=rain T_LEGDRY="no precipitation" T_POP=rain
		T_SUN=SUN T_UV="UV INDEX" T_POLLEN=POLLEN T_SUNRISE=Sunrise T_SUNSET=Sunset
		T_UVLV="Low|Moderate|High|Very high|Extreme" T_POLLV="Low|Moderate|High|Very high"
		T_NOPOLLEN="no pollen" T_NODATA2="no data"
		T_M_FLIP="Rotate screen 180°" T_M_VIEW="View:" T_V_SIMPLE=simple T_V_LIST="5-day list"
		T_M_ORIENT="Orientation:" T_O_P=portrait T_O_L=landscape T_M_REFRESH="Refresh weather"
		T_M_TEMP="Temperature:" T_M_CLOCK="Clock:" T_M_LANG="Language: Romanian"
	else
		UI_LANG=ro
		T_UNTIL="până la" T_NOW=acum T_RAIN=Ploaie T_RAINFROM="Ploaie de la" T_MAX=maxim
		T_SNOW=Ninsoare T_SNOWFROM="Ninsoare de la" T_RAINW=Plouă T_SNOWW=Ninge
		T_UPDATED=actualizat T_NODATA="fără date din" T_LOADING="Se descarcă vremea…"
		T_UPDATING="se actualizează…" T_RETURN="Revenire la Kindle…"
		T_LIGHTT=LUMINA T_LIGHTOFF="LUMINA STINSĂ" T_LIGHTH1="Glisează în sus sau în jos" T_LIGHTH2="pe marginea stângă a ecranului." T_PICK="Alege județul" T_PICKTOWN="alege localitatea"
		T_BACK=Înapoi T_PAGE=Pagina T_CLOSE=Închide T_NEXT=Înainte
		T_FEELS=Resimțit T_WIND=Vânt T_HI=Max T_LO=Min T_CHARGING="Se încarcă" T_CHARGEME="Încarcă bateria"
		T_WARN="GALBEN PORTOCALIU ROȘU" T_WARNCODE=COD T_NOWARN="FĂRĂ AVERTIZĂRI METEO"
		T_DAY1=MÂINE T_DAY2=POIMÂINE T_NEXT12="URMĂTOARELE 12 ORE" T_NOWMARK=acum T_RAINUP=PLOAIE T_SNOWUP=NINSOARE
		T_LEGSNOW=ninsoare T_LEGRAIN=ploaie T_LEGDRY="fără precipitații" T_POP=ploaie
		T_SUN=SOARE T_UV="INDICE UV" T_POLLEN=POLEN T_SUNRISE=Răsărit T_SUNSET=Apus
		T_UVLV="Scăzut|Moderat|Ridicat|Foarte ridicat|Extrem" T_POLLV="Scăzut|Moderat|Ridicat|Foarte ridicat"
		T_NOPOLLEN="fără polen" T_NODATA2="fără date"
		T_M_FLIP="Întoarce ecranul 180°" T_M_VIEW="Vedere:" T_V_SIMPLE=simplă T_V_LIST="listă 5 zile"
		T_M_ORIENT="Orientare:" T_O_P=portret T_O_L=peisaj T_M_REFRESH="Actualizează vremea"
		T_M_TEMP="Temperatura:" T_M_CLOCK="Ora:" T_M_LANG="Limba: engleză"
	fi
	# Units: temperature (C or F) and clock (24 h or 12 h with AM/PM).
	UNIT_T=$(cat "$DIR/temp.sel" 2>/dev/null)
	[ "$UNIT_T" = F ] || UNIT_T=C
	CLK12=0
	[ "$(cat "$DIR/clock.sel" 2>/dev/null)" = 12 ] && CLK12=1
}

# Temperature in the chosen unit, rounded.
tconv() {
	if [ "$UNIT_T" = F ]; then
		awk -v v="$1" 'BEGIN { x = sprintf("%.0f", v * 9 / 5 + 32); if (x == "-0") x = "0"; print x }'
	else
		round "$1"
	fi
}
load_lang

# Night hours (NIGHT_START to NIGHT_END, e.g. 23 to 6): weather fetched less often, light off.
is_night() {
	nh=$(date +%H)
	nh=${nh#0}
	ns=${NIGHT_START:-23} ne=${NIGHT_END:-6}
	if [ "$ns" -gt "$ne" ]; then
		[ "$nh" -ge "$ns" ] || [ "$nh" -lt "$ne" ]
	else
		[ "$nh" -ge "$ns" ] && [ "$nh" -lt "$ne" ]
	fi
}

# Minutes between weather fetches now: NIGHT_WEATHER_MINUTES at night, else WEATHER_MINUTES.
weather_minutes() {
	if is_night; then echo "${NIGHT_WEATHER_MINUTES:-60}"; else echo "$WEATHER_MINUTES"; fi
}

is_running() {
	[ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

# --- Weather ---------------------------------------------------------------

# Extract the body of a top-level JSON object, e.g. "current":{...}.
# Open-Meteo responses are a single line and these objects contain no nested braces.
json_obj() {
	sed -n "s/.*\"$2\":{\([^}]*\)}.*/\1/p" "$1"
}

# Scalar number from an object body.
json_num() {
	echo "$1" | sed -n "s/.*\"$2\":\(-\{0,1\}[0-9.]*\).*/\1/p"
}

# Array body (comma separated) from an object body.
json_arr() {
	echo "$1" | sed -n "s/.*\"$2\":\[\([^]]*\)\].*/\1/p"
}

# Fetch the forecast and atomically rewrite $WEATHER_ENV. Returns non-zero on failure.

# Fetch the forecast and atomically rewrite $WEATHER_ENV. Returns non-zero on failure.
fetch_weather() {
	mkdir -p "$STATE"
	tz_enc=$(echo "$TZ_IANA" | sed 's#/#%2F#g')
	url="http://api.open-meteo.com/v1/forecast?latitude=$LATITUDE&longitude=$LONGITUDE"
	url="$url&current=temperature_2m,weather_code,precipitation,is_day,cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,apparent_temperature,wind_speed_10m"
	url="$url&hourly=precipitation_probability,precipitation,weather_code,snowfall"
	url="$url&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max,sunrise,sunset,uv_index_max"
	url="$url&forecast_days=6&forecast_hours=$RAIN_LOOKAHEAD_HOURS&timezone=$tz_enc"
	[ -n "$MODEL" ] && url="$url&models=$MODEL"

	json=$STATE/weather.json
	if ! curl -s -f -m 20 -o "$json.tmp" "$url"; then
		log "weather: fetch failed"
		return 1
	fi
	mv "$json.tmp" "$json"

	cur=$(json_obj "$json" current)
	hourly=$(json_obj "$json" hourly)
	daily=$(json_obj "$json" daily)

	temp=$(json_num "$cur" temperature_2m)
	code=$(json_num "$cur" weather_code)
	precip=$(json_num "$cur" precipitation)
	is_day=$(json_num "$cur" is_day)
	cloud=$(json_num "$cur" cloud_cover)
	cloud_low=$(json_num "$cur" cloud_cover_low)
	cloud_mid=$(json_num "$cur" cloud_cover_mid)
	cloud_high=$(json_num "$cur" cloud_cover_high)
	feels=$(json_num "$cur" apparent_temperature)
	wind=$(json_num "$cur" wind_speed_10m)
	if [ -z "$temp" ] || [ -z "$code" ]; then
		log "weather: unexpected response: $(cut -c1-300 "$json" 2>/dev/null)"
		return 1
	fi

	# The model code says "overcast" (3) too often. When the sky codes 1-3 are reported, use
	# the cloud cover (%) instead: under 20 clear, under 45 mostly clear, under 80 partly cloudy.
	# CLOUD_REFINE=2 counts only the low and mid clouds (high, thin cirrus is ignored), combined
	# as overlapping at random: low + mid - low*mid/100. Falls back to the total cover.
	raw_code=$code
	sky=$cloud
	if [ "${CLOUD_REFINE:-2}" = 2 ] && [ -n "$cloud_low" ] && [ -n "$cloud_mid" ]; then
		l=${cloud_low%.*}; m=${cloud_mid%.*}
		sky=$((l + m - l * m / 100))
	fi
	if [ "${CLOUD_REFINE:-2}" != 0 ] && [ -n "$sky" ] && [ "$code" -le 3 ] 2>/dev/null; then
		c=${sky%.*}
		if [ "$c" -lt 20 ]; then code=0
		elif [ "$c" -lt 45 ]; then code=1
		elif [ "$c" -lt 80 ]; then code=2
		else code=3; fi
		# Low clouds (stratus) are what hides the sky. Models spread them thin over their grid
		# cell, so 35% low cover usually looks fully grey from the ground: show it as overcast.
		lo=${cloud_low%.*}
		if [ "${CLOUD_REFINE:-2}" = 2 ] && [ -n "$lo" ] && [ "$lo" -ge "${LOW_OVERCAST:-35}" ]; then code=3; fi
	fi
	# The model code can say overcast (3) or fog while it rains: on 27 Oct icon_seamless gave 3
	# for hours of drizzle. When the code has no precipitation, look at the amount (mm in the
	# last 15 minutes, or this hour) and at this hour's probability, and show drizzle, rain or
	# snow instead: 0.5 mm or more = rain, 0.1 mm = drizzle, nothing but >= 60% = light drizzle.
	hp=$(json_arr "$hourly" precipitation | cut -d, -f1)
	hpop=$(json_arr "$hourly" precipitation_probability | cut -d, -f1)
	hsn=$(json_arr "$hourly" snowfall | cut -d, -f1)
	case $code in
	0 | 1 | 2 | 3 | 45 | 48)
		wet=$(awk -v a="$precip" -v b="$hp" -v p="$hpop" -v sn="$hsn" -v t="$temp" 'BEGIN {
			m = a + 0; if (b + 0 > m) m = b + 0
			snow = (sn + 0 > 0 || t + 0 <= 0)
			if (m >= 0.5) print (snow ? 71 : 61)
			else if (m >= 0.1) print (snow ? 71 : 53)
			else if (p + 0 >= 60) print (snow ? 71 : 51)
		}')
		[ -n "$wet" ] && code=$wet
		;;
	esac
	log "weather: model=${MODEL:-best_match} precip=$precip hour_mm=$hp hour_pop=$hpop% temp=$temp feels=$feels wind=$wind cloud=${cloud}% low=${cloud_low}% mid=${cloud_mid}% high=${cloud_high}% sky=${sky}% model_code=$raw_code shown_code=$code day=$is_day"

	tmax=$(json_arr "$daily" temperature_2m_max | cut -d, -f1)
	tmin=$(json_arr "$daily" temperature_2m_min | cut -d, -f1)
	# Today's sunrise and sunset as HH:MM (sunset also drives the automatic light) and UV index.
	sunrise=$(json_arr "$daily" sunrise | cut -d, -f1 | sed -n 's/.*T\([0-9][0-9]:[0-9][0-9]\).*/\1/p')
	sunset=$(json_arr "$daily" sunset | cut -d, -f1 | sed -n 's/.*T\([0-9][0-9]:[0-9][0-9]\).*/\1/p')
	uv=$(json_arr "$daily" uv_index_max | cut -d, -f1)
	case $uv in null | "") uv="" ;; *) uv=$(round "$uv") ;; esac

	# The next five days (today, the first entry, is skipped): weekday names and day of the
	# month (computed here; BusyBox date cannot parse dates), weather codes, rounded high/low
	# and the day's highest precipitation probability.
	days=$(awk -v times="$(json_arr "$daily" time)" \
		-v codes="$(json_arr "$daily" weather_code)" \
		-v maxs="$(json_arr "$daily" temperature_2m_max)" \
		-v mins="$(json_arr "$daily" temperature_2m_min)" \
		-v pops="$(json_arr "$daily" precipitation_probability_max)" '
		function r(v,  x) { x = sprintf("%.0f", v); return (x == "-0") ? "0" : x }
		BEGIN {
			split("0 3 2 5 0 3 5 1 4 6 2 4", off, " ")
			split("Dum Lun Mar Mie Joi Vin Sâm", name, " ")
			n = split(times, t, ","); split(codes, c, ","); split(maxs, hi, ",")
			split(mins, lo, ","); split(pops, p, ",")
			ds = ""; dd = ""; cs = ""; his = ""; los = ""; ps = ""
			for (i = 2; i <= n; i++) {
				if (hi[i] == "null" || lo[i] == "null") continue
				gsub(/"/, "", t[i])
				y = substr(t[i], 1, 4) + 0; m = substr(t[i], 6, 2) + 0; d = substr(t[i], 9, 2) + 0
				dm = d
				if (m < 3) y--
				w = (y + int(y / 4) - int(y / 100) + int(y / 400) + off[m] + d) % 7
				# BusyBox awk reads `sep (...)` as a call to a function sep: no
				# parenthesised term directly after a variable in a concatenation.
				sep = (ds == "") ? "" : " "
				cv = (c[i] == "null") ? "-1" : c[i]
				pv = (p[i] == "null") ? 0 : sprintf("%d", p[i])
				hv = r(hi[i]); lv = r(lo[i])
				ds = ds sep name[w + 1]
				dd = dd sep dm
				cs = cs sep cv; his = his sep hv; los = los sep lv; ps = ps sep pv
			}
			printf "W_D_DAYS=\"%s\"\nW_D_DATES=\"%s\"\nW_D_CODES=\"%s\"\n", ds, dd, cs
			printf "W_D_MAX=\"%s\"\nW_D_MIN=\"%s\"\nW_D_POP=\"%s\"\n", his, los, ps
		}')

	# Per-hour series for the precipitation chart (hour, probability, wet flag, snow flag), the
	# first wet hour, the hour that wet run ends (empty if it outlasts the window), the max
	# probability, and whether most wet hours bring snow (W_SNOW_MAJ=1).
	rain=$(awk -v times="$(json_arr "$hourly" time)" \
		-v probs="$(json_arr "$hourly" precipitation_probability)" \
		-v amts="$(json_arr "$hourly" precipitation)" \
		-v codes="$(json_arr "$hourly" weather_code)" \
		-v snows="$(json_arr "$hourly" snowfall)" \
		-v thr="$RAIN_PROBABILITY" '
		BEGIN {
			n = split(times, t, ","); split(probs, p, ","); split(amts, a, ",")
			split(codes, c, ","); split(snows, s, ",")
			hours = ""; ps = ""; wets = ""; sns = ""; at = ""; stop = ""; maxp = 0; nsn = 0; nrn = 0
			for (i = 1; i <= n; i++) {
				gsub(/"/, "", t[i]); hr = substr(t[i], 12, 5)
				pv = (p[i] == "null") ? 0 : p[i] + 0
				av = (a[i] == "null") ? 0 : a[i] + 0
				cv = (c[i] == "null") ? 0 : c[i] + 0
				sv = (s[i] == "null") ? 0 : s[i] + 0
				wet = (pv >= thr || av >= 0.1) ? 1 : 0
				sn = ((cv >= 71 && cv <= 77) || cv == 85 || cv == 86 || sv > 0) ? 1 : 0
				if (wet) { if (sn) nsn++; else nrn++ }
				if (pv > maxp) maxp = pv
				if (at == "" && wet) at = hr
				else if (at != "" && stop == "" && !wet) stop = hr
				sep = (i > 1) ? " " : ""
				hours = hours sep hr
				ps = ps sep sprintf("%d", pv)
				wets = wets sep wet
				sns = sns sep sn
			}
			printf "W_HOURS=\"%s\"\nW_PROBS=\"%s\"\nW_WET=\"%s\"\nW_SNOWY=\"%s\"\n", hours, ps, wets, sns
			printf "W_RAIN_AT=\"%s\"\nW_RAIN_END=\"%s\"\nW_RAIN_MAXP=%d\nW_SNOW_MAJ=%d\n", at, stop, maxp, (nsn > nrn) ? 1 : 0
		}')

	{
		echo "W_TEMP=$temp"
		echo "W_CODE=$code"
		echo "W_PRECIP=${precip:-0}"
		echo "W_IS_DAY=${is_day:-1}"
		echo "W_CLOUD=${cloud:-}"
		echo "W_FEELS=${feels:-}"
		echo "W_WIND=${wind:-}"
		echo "W_TMAX=$tmax"
		echo "W_TMIN=$tmin"
		echo "W_SUNRISE=$sunrise"
		echo "W_SUNSET=$sunset"
		echo "W_UV=$uv"
		echo "$rain"
		echo "$days"
		echo "W_FETCHED=$(date +%s)"
	} >"$WEATHER_ENV.tmp" && mv "$WEATHER_ENV.tmp" "$WEATHER_ENV"
	return 0
}

# Pollen from the Open-Meteo air quality service (Europe, in season). The plant with the highest
# level is kept in $POLLEN_ENV: POLLEN_LVL 1 low .. 4 very high, 0 no data; POLLEN_PLANT.
POLLEN_ENV=$STATE/pollen.env

fetch_pollen() {
	[ "${POLLEN:-1}" = 1 ] || return 0
	url="http://air-quality-api.open-meteo.com/v1/air-quality?latitude=$LATITUDE&longitude=$LONGITUDE"
	url="$url&current=alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen"
	pj=$STATE/pollen.json
	if ! curl -s -f -m 20 -o "$pj.tmp" "$url"; then
		log "pollen: fetch failed"
		return 1
	fi
	mv "$pj.tmp" "$pj"
	pc=$(json_obj "$pj" current)
	# Levels by grains/m3: trees 15/90/1500, grasses 5/20/200, weeds 10/50/500.
	res=$(echo "$pc" | awk -F, '
		BEGIN {
			split("alder birch olive grass mugwort ragweed", plant, " ")
			t1["alder"] = 15; t2["alder"] = 90; t3["alder"] = 1500
			t1["birch"] = 15; t2["birch"] = 90; t3["birch"] = 1500
			t1["olive"] = 15; t2["olive"] = 90; t3["olive"] = 1500
			t1["grass"] = 5; t2["grass"] = 20; t3["grass"] = 200
			t1["mugwort"] = 10; t2["mugwort"] = 50; t3["mugwort"] = 500
			t1["ragweed"] = 10; t2["ragweed"] = 50; t3["ragweed"] = 500
		}
		{
			best = 0; bp = ""; bv = -1; seen = 0
			for (i = 1; i <= NF; i++) {
				split($i, kv, ":"); k = kv[1]; v = kv[2]; gsub(/"/, "", k); sub(/_pollen$/, "", k)
				if (!(k in t1) || v == "null" || v == "") continue
				v += 0; seen = 1
				lv = (v < t1[k]) ? 1 : (v < t2[k]) ? 2 : (v < t3[k]) ? 3 : 4
				if (lv > best || (lv == best && v > bv)) { best = lv; bp = k; bv = v }
			}
			if (!seen) best = 0
			if (bv <= 0) bp = ""
			printf "POLLEN_LVL=%d\nPOLLEN_PLANT=%s\n", best, bp
		}')
	echo "$res" >"$POLLEN_ENV.tmp" && mv "$POLLEN_ENV.tmp" "$POLLEN_ENV"
	log "pollen: $(echo "$res" | tr '\n' ' ')"
	return 0
}
# --- Weather warnings (MeteoAlarm) -------------------------------------------
# The country's feed lists the warnings of every county. The chosen place's county comes from
# cities.txt (WARN_AREA overrides it). The two highest warnings active now or starting within
# 24 h are kept in $WARN_ENV: level (1 yellow, 2 orange, 3 red), type, start and end (epoch s).
WARN_ENV=$STATE/warn.env

# Lower case without Romanian diacritics, so "Călărași" matches "Calarasi".
fold_ro() {
	# One expression per letter: BusyBox sed matches bytes, so no [ăâ] brackets.
	sed 's/ă/a/g; s/â/a/g; s/Ă/a/g; s/Â/a/g; s/î/i/g; s/Î/i/g; s/ș/s/g; s/ş/s/g; s/Ș/s/g; s/Ş/s/g; s/ț/t/g; s/ţ/t/g; s/Ț/t/g; s/Ţ/t/g' | tr 'A-Z' 'a-z'
}

warn_area() {
	if [ -n "$WARN_AREA" ]; then
		echo "$WARN_AREA"
	else
		awk -F'|' -v t="$PLACE" '$1 != "*" && $2 == t { print $1; exit }' "$CITIES" 2>/dev/null
	fi
}


fetch_warnings() {
	[ "${WARNINGS:-1}" = 1 ] || return 0
	area=$(warn_area)
	[ -n "$area" ] || area=$PLACE
	key=$(echo "$area" | fold_ro)
	feed=$STATE/warn.xml
	via=""
	# Plain HTTP first (the Kindle's curl is old); HTTPS without certificate checks as a fallback.
	for u in "http://${WARN_FEED:-feeds.meteoalarm.org/feeds/meteoalarm-legacy-atom-romania}" \
		"https://${WARN_FEED:-feeds.meteoalarm.org/feeds/meteoalarm-legacy-atom-romania}"; do
		if curl -s -f -k -L -m 30 -o "$feed.tmp" "$u"; then
			via=${u%%:*}
			break
		fi
	done
	if [ -z "$via" ]; then
		log "warn: fetch failed over http and https"
		return 1
	fi
	mv "$feed.tmp" "$feed"
	# One <entry> a line; title "Orange Wind Warning issued for Romania - ...", times like
	# 2026-10-25T13:00:00+00:00 turned into epoch seconds by hand (BusyBox awk has no mktime).
	# Warnings of the same level and type are merged (earliest start, latest end; the feed also
	# repeats a warning as updates). The two highest are kept: WARN1_* and WARN2_*.
	res=$(tr '\n\r' '  ' <"$feed" | fold_ro | sed 's/<entry/\
<entry/g' | awk -v key="$key" -v now="$(date +%s)" '
		function tag(n,  s) {
			if (!match($0, "<" n "[^>]*>[^<]*</" n ">")) return ""
			s = substr($0, RSTART, RLENGTH); sub(/^<[^>]*>/, "", s); sub(/<.*$/, "", s); return s
		}
		function ep(s,  y, mo, d, z, off, days) {
			if (s == "") return 0
			y = substr(s, 1, 4) + 0; mo = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
			off = 0; z = substr(s, 20, 1)
			if (z == "+" || z == "-") { off = (substr(s, 21, 2) * 60 + substr(s, 24, 2)) * 60; if (z == "-") off = -off }
			if (mo <= 2) { y--; mo += 12 }
			days = 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (mo - 3) + 2) / 5) + d - 719469
			return days * 86400 + substr(s, 12, 2) * 3600 + substr(s, 15, 2) * 60 - off
		}
		/^<entry/ {
			n++
			a = tag("cap:areadesc")
			# No parenthesised term right after a variable: BusyBox awk would call it as a function.
			if (areas < 4 && index(seen, "|" a "|") == 0) { seen = seen "|" a "|"; sp = areas ? "; " : ""; sample = sample sp a; areas++ }
			if (index(a, key) == 0) next
			t = tag("title"); lv = 0
			if (t ~ /^yellow/) lv = 1; else if (t ~ /^orange/) lv = 2; else if (t ~ /^red/) lv = 3
			if (lv == 0) next
			ty = t; sub(/^[a-z]+ /, "", ty); sub(/ warning.*$/, "", ty)
			on = ep(tag("cap:onset")); if (on == 0) on = ep(tag("cap:effective"))
			ex = ep(tag("cap:expires"))
			if (ex <= now || on - now > 86400) next
			m++
			k = lv "|" ty
			if (!(k in fo)) { nk++; keys[nk] = k; kl[nk] = lv; kt[nk] = ty; fo[k] = on; fe[k] = ex }
			else {
				if (on < fo[k]) fo[k] = on
				if (ex > fe[k]) fe[k] = ex
			}
		}
		END {
			# Order: higher level first, then the earlier start.
			for (i = 1; i <= nk; i++) for (j = i + 1; j <= nk; j++) {
				if (kl[j] > kl[i] || (kl[j] == kl[i] && fo[keys[j]] < fo[keys[i]])) {
					x = keys[i]; keys[i] = keys[j]; keys[j] = x
					x = kl[i]; kl[i] = kl[j]; kl[j] = x
					x = kt[i]; kt[i] = kt[j]; kt[j] = x
				}
			}
			shown = (nk > 2) ? 2 : nk
			printf "WARN_N=%d\n", shown
			for (i = 1; i <= shown; i++)
				printf "WARN%d_LEVEL=%d\nWARN%d_TYPE=\"%s\"\nWARN%d_FROM=%d\nWARN%d_UNTIL=%d\n", i, kl[i], i, kt[i], i, fo[keys[i]], i, fe[keys[i]]
			printf "WARN_LOG=\"%d entries, %d for this area, %d kinds, areas like: %s\"\n", n, m, nk, sample
		}')
	echo "$res" >"$WARN_ENV.tmp" && mv "$WARN_ENV.tmp" "$WARN_ENV"
	eval "$res"
	log "warn: via $via, area=$key, $WARN_LOG; shown $WARN_N: ${WARN1_LEVEL:-} ${WARN1_TYPE:-} ${WARN2_LEVEL:-} ${WARN2_TYPE:-}"
	return 0
}

# Round a decimal to the nearest integer (handles negatives).
round() {
	awk -v v="$1" 'BEGIN { printf "%.0f", v }'
}

# WMO weather code -> icon name (day/night aware) and short description.
# Forecast weekday abbreviation: fetched in Romanian, shown in the UI language.
wd_name() {
	[ "$UI_LANG" = en ] || { echo "$1"; return; }
	case $1 in
	Dum) echo Sun ;;
	Lun) echo Mon ;;
	Mar) echo Tue ;;
	Mie) echo Wed ;;
	Joi) echo Thu ;;
	Vin) echo Fri ;;
	*) echo Sat ;;
	esac
}

# Romanian date line, e.g. "Sâmbătă, 24 octombrie" (the Kindle has no locale data).
ro_date() {
	if [ "$UI_LANG" = en ]; then
		set -- $(date '+%d')
		echo "$(date '+%A, %B') ${1#0}"
		return
	fi
	set -- $(date '+%w %d %m')
	case $1 in
	0) rd_wd="Duminică" ;;
	1) rd_wd="Luni" ;;
	2) rd_wd="Marți" ;;
	3) rd_wd="Miercuri" ;;
	4) rd_wd="Joi" ;;
	5) rd_wd="Vineri" ;;
	*) rd_wd="Sâmbătă" ;;
	esac
	rd_d=${2#0}
	case ${3#0} in
	1) rd_mo=ianuarie ;;
	2) rd_mo=februarie ;;
	3) rd_mo=martie ;;
	4) rd_mo=aprilie ;;
	5) rd_mo=mai ;;
	6) rd_mo=iunie ;;
	7) rd_mo=iulie ;;
	8) rd_mo=august ;;
	9) rd_mo=septembrie ;;
	10) rd_mo=octombrie ;;
	11) rd_mo=noiembrie ;;
	*) rd_mo=decembrie ;;
	esac
	echo "$rd_wd, $rd_d $rd_mo"
}

describe() {
	code=$1
	day=$2
	sfx=night
	[ "$day" = 1 ] && sfx=day
	case $code in
	0) ICON=clear-$sfx; DESC="Senin" ;;
	1) ICON=partly-$sfx; DESC="Aproape senin" ;;
	2) ICON=partly-$sfx; DESC="Parțial noros" ;;
	3) ICON=cloudy; DESC="Înnorat" ;;
	45 | 48) ICON=fog; DESC="Ceață" ;;
	51 | 53 | 55) ICON=drizzle; DESC="Burniță" ;;
	56 | 57) ICON=drizzle; DESC="Burniță înghețată" ;;
	61) ICON=rain; DESC="Ploaie slabă" ;;
	63) ICON=rain; DESC="Ploaie" ;;
	65) ICON=rain; DESC="Ploaie intensă" ;;
	66 | 67) ICON=rain; DESC="Ploaie înghețată" ;;
	71) ICON=snow; DESC="Ninsoare slabă" ;;
	73) ICON=snow; DESC="Ninsoare" ;;
	75) ICON=snow; DESC="Ninsoare intensă" ;;
	77) ICON=snow; DESC="Zăpadă fină" ;;
	80) ICON=rain; DESC="Averse slabe" ;;
	81) ICON=rain; DESC="Averse" ;;
	82) ICON=rain; DESC="Averse intense" ;;
	85 | 86) ICON=snow; DESC="Averse de ninsoare" ;;
	95) ICON=thunder; DESC="Furtună" ;;
	96 | 99) ICON=thunder; DESC="Furtună cu grindină" ;;
	*) ICON=cloudy; DESC="Cod $code" ;;
	esac
	if [ "$UI_LANG" = en ]; then
		case $code in
		0) DESC="Clear" ;;
		1) DESC="Mostly clear" ;;
		2) DESC="Partly cloudy" ;;
		3) DESC="Overcast" ;;
		45 | 48) DESC="Fog" ;;
		51 | 53 | 55) DESC="Drizzle" ;;
		56 | 57) DESC="Freezing drizzle" ;;
		61) DESC="Light rain" ;;
		63) DESC="Rain" ;;
		65) DESC="Heavy rain" ;;
		66 | 67) DESC="Freezing rain" ;;
		71) DESC="Light snow" ;;
		73) DESC="Snow" ;;
		75) DESC="Heavy snow" ;;
		77) DESC="Snow grains" ;;
		80) DESC="Light showers" ;;
		81) DESC="Showers" ;;
		82) DESC="Heavy showers" ;;
		85 | 86) DESC="Snow showers" ;;
		95) DESC="Thunderstorm" ;;
		96 | 99) DESC="Thunderstorm, hail" ;;
		*) DESC="Code $code" ;;
		esac
	fi
	case $code in
	71 | 73 | 75 | 77 | 85 | 86) WET_NOW="Snowing now" ;;
	5? | 6? | 8? | 9?) WET_NOW="Raining now" ;;
	*) WET_NOW="" ;;
	esac
}


# Warning types in capitals for the warning box (MeteoAlarm's English words, comma separated).
warn_type_up() {
	wu_out=""
	for w in $(echo "$1" | tr ',' ' '); do
		if [ "$UI_LANG" = en ]; then
			wu_w=$(echo "$w" | tr '-' ' ' | tr 'a-z' 'A-Z')
		else
			case $w in
			wind) wu_w=VÂNT ;;
			snow-ice | snow/ice) wu_w="NINSOARE, POLEI" ;;
			thunderstorm*) wu_w=FURTUNI ;;
			fog) wu_w=CEAȚĂ ;;
			high-temperature*) wu_w=CANICULĂ ;;
			low-temperature*) wu_w=GER ;;
			coastal*) wu_w="FENOMENE COSTIERE" ;;
			forest-fire*) wu_w="RISC DE INCENDIU" ;;
			avalanche*) wu_w=AVALANȘE ;;
			rain-flood*) wu_w="PLOI, INUNDAȚII" ;;
			rain*) wu_w=PLOI ;;
			flood*) wu_w=INUNDAȚII ;;
			*) wu_w=$(echo "$w" | tr 'a-z' 'A-Z') ;;
			esac
		fi
		wu_out="${wu_out:+$wu_out, }$wu_w"
	done
	echo "$wu_out"
}

# Weekday and time of an epoch time, e.g. "Lun 09:40" ("Mon 09:40").
warn_day() {
	set -- "$(date -d "@$1" '+%u %H:%M' 2>/dev/null)"
	if [ "$UI_LANG" = en ]; then set -- "${1#* }" Mon Tue Wed Thu Fri Sat Sun ${1%% *}
	else set -- "${1#* }" Lun Mar Mie Joi Vin Sâm Dum ${1%% *}; fi
	eval "echo \"\${$(( ${9} + 1 ))} \$1\""
}

# Weekday in capitals for the day headers ("MIE", "WED").
# Capitals, Romanian letters included (tr alone does not know them).
upper() {
	echo "$1" | sed 's/ă/Ă/g; s/â/Â/g; s/î/Î/g; s/ș/Ș/g; s/ş/Ş/g; s/ț/Ț/g; s/ţ/Ţ/g' | tr 'a-z' 'A-Z'
}

wd_upper() {
	case $(wd_name "$1") in
	Dum) echo DUM ;; Lun) echo LUN ;; Mar) echo MAR ;; Mie) echo MIE ;; Joi) echo JOI ;;
	Vin) echo VIN ;; Sâm) echo SÂM ;;
	*) wd_name "$1" | tr 'a-z' 'A-Z' ;;
	esac
}

# County of the chosen place, from cities.txt (empty if it is not listed).
place_county() {
	awk -F'|' -v t="$PLACE" '$1 != "*" && $2 == t { print $1; exit }' "$CITIES" 2>/dev/null
}

# Licence plate code of a Romanian county ("Călărași" -> CL).
county_code() {
	case $1 in
	Alba) echo AB ;; Arad) echo AR ;; Argeș) echo AG ;; Bacău) echo BC ;; Bihor) echo BH ;;
	Bistrița-Năsăud) echo BN ;; Botoșani) echo BT ;; Brașov) echo BV ;; Brăila) echo BR ;;
	București) echo B ;; Buzău) echo BZ ;; Caraș-Severin) echo CS ;; Cluj) echo CJ ;;
	Constanța) echo CT ;; Covasna) echo CV ;; Călărași) echo CL ;; Dolj) echo DJ ;;
	Dâmbovița) echo DB ;; Galați) echo GL ;; Giurgiu) echo GR ;; Gorj) echo GJ ;;
	Harghita) echo HR ;; Hunedoara) echo HD ;; Ialomița) echo IL ;; Iași) echo IS ;;
	Ilfov) echo IF ;; Maramureș) echo MM ;; Mehedinți) echo MH ;; Mureș) echo MS ;;
	Neamț) echo NT ;; Olt) echo OT ;; Prahova) echo PH ;; "Satu Mare") echo SM ;;
	Sibiu) echo SB ;; Suceava) echo SV ;; Sălaj) echo SJ ;; Teleorman) echo TR ;;
	Timiș) echo TM ;; Tulcea) echo TL ;; Vaslui) echo VS ;; Vrancea) echo VN ;; Vâlcea) echo VL ;;
	esac
}

# "Călărași, CL": the place with its county code.
city_label() {
	cl_c=$(county_code "$(place_county)")
	echo "$PLACE${cl_c:+, $cl_c}"
}

# Word N (from 1) of a space separated list.
nth() {
	nth_i=$1
	set -- $2
	eval "echo \"\${$nth_i}\""
}

# --- Drawing ---------------------------------------------------------------

# The screens are authored at the Paperwhite's own resolution: a 758x1024 canvas in portrait,
# 1024x758 in landscape (ORIENT). layout_init scales it uniformly to the real screen and centers
# it, so the same numbers work on other Kindles. The city picker keeps the older 600x800 canvas
# (layout_init small, no longer used). Every helper below takes canvas coordinates.
# REKINDLE_VIEW=WxH overrides the target size (testing other sizes on one device).
layout_init() {
	CW=758 CH=1024
	[ "$ORIENT" = landscape ] && CW=1024 CH=758
	if [ "$1" = small ]; then
		CW=600 CH=800
		[ "$ORIENT" = landscape ] && CW=800 CH=600
	fi
	eval "$(fbink -e | tr ';' '\n' | grep -e '^viewWidth=' -e '^viewHeight=')"
	SCR_W=${viewWidth:-600}
	SCR_H=${viewHeight:-800}
	tw=$SCR_W th=$SCR_H
	if [ -n "$REKINDLE_VIEW" ]; then
		tw=${REKINDLE_VIEW%x*} th=${REKINDLE_VIEW#*x}
	fi
	# Scale in thousandths: the smaller of the two axis ratios, so nothing overflows.
	S=$((tw * 1000 / CW))
	[ $((th * 1000 / CH)) -lt "$S" ] && S=$((th * 1000 / CH))
	OX=$(((SCR_W - CW * S / 1000) / 2))
	OY=$(((SCR_H - CH * S / 1000) / 2))
	set_bands
}

# Canvas -> device: positions (offset + scale) and lengths (scale, at least 1 px).
px_x() { echo $((OX + $1 * S / 1000)); }
px_y() { echo $((OY + $1 * S / 1000)); }
px_len() {
	v=$(($1 * S / 1000))
	[ "$v" -lt 1 ] && v=1
	echo "$v"
}

# Text helpers: nothing is refreshed (-b); `--` lets text start with "-" (negative temperatures).
# Font sizes are FBInk px: the height of the line (ascent + descent), about 1.12 x the em size.
# fb_text FONT PX TOP LEFT RIGHT TEXT [extra fbink flags...]: centered in the [LEFT, CW-RIGHT] band.
fb_text() {
	font=$1 px=$(px_len "$2") top=$(px_y "$3") left=$(px_x "$4") text=$6
	right=$((SCR_W - $(px_x $((CW - $5)))))
	shift 6
	fbink -q -b -m "$@" -t regular="$font",px="$px",top="$top",left="$left",right="$right" -- "$text" >/dev/null 2>&1
}

# fb_ltext FONT PX TOP LEFT TEXT [extra fbink flags...]: left edge at LEFT.
fb_ltext() {
	font=$1 px=$(px_len "$2") top=$(px_y "$3") left=$(px_x "$4") text=$5
	shift 5
	fbink -q -b "$@" -t regular="$font",px="$px",top="$top",left="$left" -- "$text" >/dev/null 2>&1
}

# fb_rtext FONT PX TOP RIGHT_EDGE TEXT [extra fbink flags...]: right edge at RIGHT_EDGE.
# Sets RTEXT_LEFT to the text's left edge (canvas units) for placing things before it.
fb_rtext() {
	rfont=$1 rpx=$(px_len "$2") rtop=$(px_y "$3") rtext=$5
	w=$(text_width "$rfont" "$rpx" "$rtext")
	rx=$(($(px_x "$4") - ${w:-0}))
	RTEXT_LEFT=$(((rx - OX) * 1000 / S))
	shift 5
	fbink -q -b "$@" -t regular="$rfont",px="$rpx",top="$rtop",left="$rx" -- "$rtext" >/dev/null 2>&1
}

# fb_ctext FONT PX TOP CENTER_X TEXT [extra fbink flags...]: centered on CENTER_X.
fb_ctext() {
	c_f=$1 c_p=$2 c_t=$3 c_s=$5
	c_w=$(tw_c "$c_f" "$c_p" "$c_s")
	c_x=$(($4 - c_w / 2))
	shift 5
	fb_ltext "$c_f" "$c_p" "$c_t" "$c_x" "$c_s" "$@"
}

fb_rect() {
	# fb_rect TOP LEFT WIDTH HEIGHT COLOR
	fbink -q -b -B "$5" -k top="$(px_y "$1")",left="$(px_x "$2")",width="$(px_len "$3")",height="$(px_len "$4")" >/dev/null 2>&1
}

# fb_frame TOP LEFT WIDTH HEIGHT: white box with a 2 px black outline.
fb_frame() {
	fb_rect "$1" "$2" "$3" "$4" BLACK
	fb_rect $(($1 + 2)) $(($2 + 2)) $(($3 - 4)) $(($4 - 4)) WHITE
}

# fb_band TOP LEFT WIDTH HEIGHT: light gray label band with a 2 px black outline (black text
# goes on top; white text did not show on the Kindle's FBInk).
fb_band() {
	fb_rect "$1" "$2" "$3" "$4" BLACK
	fb_rect $(($1 + 2)) $(($2 + 2)) $(($3 - 4)) $(($4 - 4)) GRAYD
}

# fb_pill TOP LEFT WIDTH HEIGHT [WHITE|GRAYA]: like fb_band, with rounded ends (ui/cod-st.png
# and cod-dr.png, 12 px wide, made for HEIGHT 42) as on the other boxes; light gray, or white,
# or medium gray (cod-st-gri.png).
fb_pill() {
	case $5 in WHITE) pl_c=-alb ;; GRAYA) pl_c=-gri ;; *) pl_c="" ;; esac
	fb_rect "$1" $(($2 + 12)) $(($3 - 24)) "$4" BLACK
	fb_rect $(($1 + 2)) $(($2 + 12)) $(($3 - 24)) $(($4 - 4)) "${5:-GRAYD}"
	fb_image "$DIR/ui/cod-st$pl_c.png" "$2" "$1" 12 "$4"
	fb_image "$DIR/ui/cod-dr$pl_c.png" $(($2 + $3 - 12)) "$1" 12 "$4"
}

# fb_refresh TOP LEFT WIDTH HEIGHT: refresh only this rectangle of the screen (non-flashing).
fb_refresh() {
	fbink -q -s top="$(px_y "$1")",left="$(px_x "$2")",width="$(px_len "$3")",height="$(px_len "$4")" >/dev/null 2>&1
}

# fb_image FILE X Y W H: draw an image scaled to W x H canvas px.
fb_image() {
	fbink -q -b -g file="$1",x="$(px_x "$2")",y="$(px_y "$3")",w="$(px_len "$4")",h="$(px_len "$5")" >/dev/null 2>&1
}

# Width in device px of TEXT at device PX in FONT, from the font's width table. FBInk scales a
# font by PX / (ascent + descent) = PX / 2288 units. Measuring with FBInk itself drew stray
# glyphs at the top left of the screen on the Kindle, so it is not used. UTF-8 is matched
# byte-wise: 3-, 2-, then 1-byte sequences. Unknown characters count as 1100 units.
text_width() {
	awk -v f="${1%.ttf}.wid" -v px="$2" -v s="$3" 'BEGIN {
		while ((getline l < f) > 0) { sp = index(l, " "); w[substr(l, sp + 1)] = substr(l, 1, sp - 1) + 0 }
		n = length(s); t = 0
		for (i = 1; i <= n; ) {
			c = substr(s, i, 3)
			if (c in w) { t += w[c]; i += 3; continue }
			c = substr(s, i, 2)
			if (c in w) { t += w[c]; i += 2; continue }
			c = substr(s, i, 1)
			t += (c in w) ? w[c] : 1100
			i++
		}
		printf "%d\n", t * px / 2288 + 0.5
	}'
}

# Width of TEXT in canvas units: tw_c FONT PX TEXT.
tw_c() {
	t_w=$(text_width "$1" "$(px_len "$2")" "$3")
	echo $((${t_w:-0} * 1000 / S))
}

# fit_px FONT PX MAXW TEXT: the largest size up to PX at which TEXT fits in MAXW canvas px.
fit_px() {
	f_p=$2
	while [ "$f_p" -gt 14 ] && [ "$(tw_c "$1" "$f_p" "$4")" -gt "$3" ]; do
		f_p=$((f_p * 92 / 100))
	done
	echo "$f_p"
}

# fb_head TOP HEIGHT CENTER_X MAXW TEXT [PX]: box title in the gray header band at TOP (HEIGHT
# incl. the outline). Capitals at about half the band's height (or at PX), shrunk to fit MAXW;
# drawn twice, 1 px apart, so it reads heavier than plain bold from a distance.
fb_head() {
	h_p=$(fit_px "$F_BOLD" "${6:-$((($2 - 4) * 76 / 100))}" $(($4 - 1)) "$5")
	h_x=$(($3 - $(tw_c "$F_BOLD" "$h_p" "$5") / 2))
	h_t=$(($1 + $2 / 2 - h_p * 485 / 1000))
	fb_ltext "$F_BOLD" "$h_p" "$h_t" "$h_x" "$5" -O
	fb_ltext "$F_BOLD" "$h_p" "$h_t" $((h_x + 1)) "$5" -O
}

# Static parts of a screen (frames, black headers, buttons): one image from ui/.
draw_chrome() {
	fb_image "$DIR/ui/$1.png" 0 0 "$CW" "$CH"
}

# Weather icon by name: icon IMAGE_LEFT IMAGE_TOP SIZE.
draw_icon() {
	fb_image "$DIR/icons/$ICON.png" "$1" "$2" "$3" "$3"
}

# The current icon with the middle of its drawing (not of the file) at CX CY, as large as
# fits: at most SIZE, the drawing at most HALF_H above and below CY and MAXW wide.
# draw_icon_c CX CY SIZE HALF_H MAXW (IC_LEFT / IC_RIGHT: edges the image must not pass,
# IC_PCT: final size in percent)
draw_icon_c() {
	set -- "$@" $(grep "^$ICON " "$DIR/icons/centru.txt" | cut -d' ' -f2-)
	[ -n "$9" ] || set -- "$1" "$2" "$3" "$4" "$5" 0 0 200 200
	ic_s=$3
	ic_h=$((${9} - $7)) ic_w=$(($8 - $6))
	[ $((ic_s * ic_h / 200)) -gt $(($4 * 2)) ] && ic_s=$(($4 * 2 * 200 / ic_h))
	[ $((ic_s * ic_w / 200)) -gt "$5" ] && ic_s=$(($5 * 200 / ic_w))
	ic_s=$((ic_s * ${IC_PCT:-100} / 100))
	# IC_FIT=1: when the square would start above IC_TOP it moves down to it, and shrinks
	# only if the drawing would then pass IC_BOT (the texts under it).
	if [ "${IC_FIT:-0}" = 1 ] && [ $(($2 - ic_s * ($7 + ${9}) / 400)) -lt "${IC_TOP:-0}" ] &&
		[ $((IC_TOP + ic_s * ${9} / 200)) -gt "$IC_BOT" ]; then
		ic_s=$(((IC_BOT - IC_TOP) * 200 / ${9}))
	fi
	ic_x=$(($1 - ic_s * ($6 + $8) / 400))
	# The file has a white background: keep it off the temperature (IC_LEFT) and inside the
	# box it sits in (IC_RIGHT).
	[ "$ic_x" -lt "${IC_LEFT:-0}" ] && ic_x=$IC_LEFT
	[ $((ic_x + ic_s)) -gt "$IC_RIGHT" ] && ic_x=$((IC_RIGHT - ic_s))
	# Nor over a line above it (IC_TOP: the first free row).
	ic_y=$(($2 - ic_s * ($7 + ${9}) / 400))
	[ "$ic_y" -lt "${IC_TOP:-0}" ] && ic_y=$IC_TOP
	draw_icon "$ic_x" "$ic_y" "$ic_s"
}

# Current temperature: a short thin minus (a bar, not the "-" glyph) centred on the height of
# the digits, the number, a small "°" level with its top and the unit ("C" or "F") on its
# baseline. temp_size PX MAXW shrinks PX until it fits MAXW and sets t_p, t_neg, t_n (digits
# only), t_mw (minus bar + gap), t_wn, t_gap, t_wu, t_u and T_W (the whole width).
temp_size() {
	t_n=$(tconv "$W_TEMP")
	t_neg=0
	case $t_n in -*) t_neg=1 t_n=${t_n#-} ;; esac
	t_p=$1
	while :; do
		t_u=$((t_p * 43 / 100))
		t_wn=$(tw_c "$F_BOLD" "$t_p" "$t_n")
		t_wu=$(tw_c "$F_BOLD" "$t_u" "$UNIT_T")
		t_gap=$((t_p / 25))
		# Minus: 30% of the digit height long, 7.5% thick, 12% from the digits (mock-ups).
		t_mw=0
		[ "$t_neg" = 1 ] && t_mw=$((t_p * 64 * 42 / 10000))
		T_W=$((t_mw + t_wn + t_gap + t_wu))
		[ "$T_W" -le "$2" ] || [ "$t_p" -lt 60 ] && break
		t_p=$((t_p * 94 / 100))
	done
}

# draw_temp LEFT BASELINE PX MAXW. Sets TEMP_END (canvas x where the unit ends).
draw_temp() {
	temp_size "$3" "$4"
	draw_temp_at "$1" "$2"
}

# draw_temp_at LEFT BASELINE: draw what temp_size measured.
draw_temp_at() {
	# FBInk px: ascent 0.81, digit height 0.64 of the size (Liberation Sans).
	t_dh=$((t_p * 64 / 100))
	t_x=$1
	if [ "$t_neg" = 1 ]; then
		t_mt=$((t_dh * 75 / 1000))
		[ "$t_mt" -lt 4 ] && t_mt=4
		fb_rect $(($2 - t_dh / 2 - t_mt / 2)) "$t_x" $((t_dh * 30 / 100)) "$t_mt" BLACK
		t_x=$((t_x + t_mw))
	fi
	fb_ltext "$F_BOLD" "$t_p" $(($2 - t_p * 81 / 100)) "$t_x" "$t_n" -O
	t_x=$((t_x + t_wn + t_gap))
	fb_ltext "$F_BOLD" "$t_u" $(($2 - t_dh - t_u * 17 / 100)) "$t_x" "°" -O
	fb_ltext "$F_BOLD" "$t_u" $(($2 - t_u * 81 / 100)) "$t_x" "$UNIT_T" -O
	TEMP_END=$((t_x + t_wu))
}

# No warning codes: the free area TOP..BOTTOM is split in two equal halves, the weather icon
# centred in the upper one and the temperature in the lower one, both on CX (mock-ups of
# 28 Oct). ICON_PCT / DIGIT_PCT: drawing and digit height as a share of a half.
# draw_now_split CX TOP BOTTOM MAXW ICON_PCT DIGIT_PCT [ICON_MAXW]
draw_now_split() {
	ns_half=$((($3 - $2) / 2))
	ns_ic=$(($2 + ns_half / 2)) ns_tc=$(($2 + ns_half + ns_half / 2))
	# The icon file (white square) is at most a half high, so a wide flat drawing such as
	# "cloudy" does not grow over the clock or the digits; drawn first, the digits go on top.
	ns_ih=$((ns_half * $5 / 100))
	IC_LEFT=0 IC_RIGHT=1024 IC_PCT=100 IC_TOP=$(($2 + 2))
	draw_icon_c "$1" "$ns_ic" "$ns_half" $((ns_ih / 2)) "${7:-$4}"
	IC_TOP=0
	# Digit height = DIGIT_PCT of the half (digit height is 0.64 of the FBInk px).
	temp_size $((ns_half * $6 * 100 / 6400)) "$4"
	t_dh=$((t_p * 64 / 100))
	draw_temp_at $(($1 - T_W / 2)) $((ns_tc + t_dh / 2))
}

# Portrait without codes: the free area LEFT..RIGHT x TOP..BOTTOM split in two equal halves
# side by side, the temperature in the left one, right-aligned on the middle (the room on its
# left takes the minus in winter), and the icon centred in the right one, both on the middle row
# of the area (mock-ups of 29 Oct). draw_now_side LEFT TOP RIGHT BOTTOM
draw_now_side() {
	nd_mid=$((($1 + $3) / 2)) nd_cy=$((($2 + $4) / 2)) nd_hw=$((($3 - $1) / 2))
	IC_LEFT=$((nd_mid + 2)) IC_RIGHT=$3 IC_PCT=100 IC_TOP=$(($2 + 2))
	draw_icon_c $((nd_mid + nd_hw / 2)) "$nd_cy" 300 $((($4 - $2) / 2 - 20)) $((nd_hw - 30))
	IC_TOP=0
	# Same size as "12°C" in the mock-ups; a longer one ("-12°C") shrinks to the half.
	temp_size 252 $((nd_hw - 12))
	t_dh=$((t_p * 64 / 100))
	# +2: the unit's right side bearing, so the "C" itself ends on the middle.
	draw_temp_at $((nd_mid + 2 - T_W)) $((nd_cy + t_dh / 2))
}

# Weekday and date, right-aligned under the clock.
draw_date() {
	fb_rtext "$F_REG" 26 "$DATE_Y" "$DATE_R" "$(ro_date)"
}

draw_clock() {
	if [ "$CLK12" = 1 ]; then
		ck=$(date '+%I:%M')
		ck_pm=$(date '+%p')
		ck_w=$(tw_c "$F_BOLD" 22 "$ck_pm")
		fb_rtext "$F_BOLD" "$CLK_PX" "$CLOCK_TOP" $((CLK_R - ck_w - 4)) "${ck#0}" -O
		fb_ltext "$F_BOLD" 22 $((CLOCK_TOP + CLK_PX * 81 / 100 - 18)) $((CLK_R - ck_w)) "$ck_pm" -O
	else
		fb_rtext "$F_BOLD" "$CLK_PX" "$CLOCK_TOP" "$CLK_R" "$(date '+%H:%M')" -O
	fi
}

# Weather warnings (MeteoAlarm): up to two, each a black label ("COD PORTOCALIU"), the type
# and the period. Portrait: right-aligned at WARN_R; landscape: left-aligned at WARN_L.
# With none, nothing is drawn (WARN_SHOWN=0) and the layouts put the icon and the temperature
# in the free space above the texts.
draw_warnings() {
	WARN_BOT=$WARN_Y HDR_END=718 WARN_SHOWN=0
	[ "${WARNINGS:-1}" = 1 ] && [ -f "$WARN_ENV" ] || return 0
	WARN_N=0
	. "$WARN_ENV"
	nowe=$(date +%s)
	wk=1 wy=$WARN_Y wshown=0 WARN_BOT=$WARN_Y
	while [ "$wk" -le "${WARN_N:-0}" ] && [ "$wshown" -lt 2 ]; do
		eval "wlv=\$WARN${wk}_LEVEL wty=\$WARN${wk}_TYPE wfr=\$WARN${wk}_FROM wun=\$WARN${wk}_UNTIL"
		wk=$((wk + 1))
		[ "${wun:-0}" -gt "$nowe" ] || continue
		set -- $T_WARN
		case $wlv in
		1) wname=$1 ;;
		2) wname=$2 ;;
		*) wname=$3 ;;
		esac
		if [ "$UI_LANG" = en ]; then wlab="$wname $T_WARNCODE"; else wlab="$T_WARNCODE $wname"; fi
		wtxt=$(warn_type_up "$wty")
		wper="$(warn_day "$wfr") – $(warn_day "$wun")"
		wlp=$(fit_px "$F_BOLD" 39 "$WARN_LW" "$wlab")
		wbw=$(($(tw_c "$F_BOLD" "$wlp" "$wlab") + 14))
		wtp=$(fit_px "$F_REG" 31 330 "$wtxt")
		# Yellow: light gray band; orange and red: medium gray (black bold text on both), and
		# red also gets a black triangle with "!" (ui/atentie.png) in the free space beside it.
		wfill=""
		[ "$wlv" -ge 2 ] && wfill=GRAYA
		# Rounded gray band with the code, then the type and the period under it (with room
		# for the accents of capitals such as "Â").
		if [ "$ORIENT" = landscape ]; then
			fb_pill "$wy" "$WARN_L" "$wbw" 42 $wfill
			[ "$wlv" -ge 3 ] && fb_image "$DIR/ui/atentie.png" $((WARN_L + wbw + 10)) "$wy" 46 42
			fb_ltext "$F_BOLD" "$wlp" $((wy + (42 - wlp) / 2)) $((WARN_L + 7)) "$wlab" -O
			fb_ltext "$F_REG" "$wtp" $((wy + 50)) $((WARN_L + 5)) "$wtxt" -O
			fb_ltext "$F_REG" 30 $((wy + 79)) $((WARN_L + 5)) "$wper" -O -C GRAY5
		else
			wsx=$((WARN_R - wbw))
			if [ "$wlv" -ge 3 ]; then
				wsx=$((wsx - 56))
				fb_image "$DIR/ui/atentie.png" "$wsx" "$wy" 46 42
			fi
			[ "$wshown" = 0 ] && HDR_END=$((wsx - 6))
			fb_pill "$wy" $((WARN_R - wbw)) "$wbw" 42 $wfill
			fb_ltext "$F_BOLD" "$wlp" $((wy + (42 - wlp) / 2)) $((WARN_R - wbw + 7)) "$wlab" -O
			fb_rtext "$F_REG" "$wtp" $((wy + 50)) $((WARN_R - 2)) "$wtxt" -O
			fb_rtext "$F_REG" 30 $((wy + 79)) $((WARN_R - 6)) "$wper" -O -C GRAY5
		fi
		wy=$((wy + 116))
		WARN_BOT=$((wy - 6))
		wshown=$((wshown + 1))
	done
	WARN_SHOWN=$wshown
}

# Hourly precipitation chart: one bar per forecast hour, height = probability; black for rain,
# dark gray for snow, light gray for dry hours; a dotted line marks RAIN_PROBABILITY and every
# third hour is labelled below. draw_precip_chart LEFT WIDTH TOP HEIGHT
draw_precip_chart() {
	cl=$1 cw=$2 ct=$3 ch=$4
	set -- $W_PROBS
	cn=$#
	[ "$cn" -gt 0 ] || return 0
	pitch=$((cw / cn))
	bw=$((pitch * 85 / 100))
	ty=$((ct + ch - RAIN_PROBABILITY * ch / 100))
	fb_image "$DIR/ui/punctat.png" "$cl" "$ty" "$cw" 2
	hrs="$W_HOURS " wets="$W_WET " sns="$W_SNOWY "
	ci=0
	for p in $W_PROBS; do
		hr=${hrs%% *} hrs=${hrs#* }
		wet=${wets%% *} wets=${wets#* }
		sn=${sns%% *} sns=${sns#* }
		bh=$((p * ch / 100))
		[ "$bh" -lt 4 ] && bh=4
		color=GRAYA
		if [ "$wet" = 1 ]; then
			color=BLACK
			[ "$sn" = 1 ] && color=GRAY5
		fi
		x=$((cl + ci * pitch + (pitch - bw) / 2))
		fb_rect $((ct + ch - bh)) "$x" "$bw" "$bh" "$color"
		[ $((ci % 3)) -eq 0 ] && fb_ltext "$F_REG" 23 $((ct + ch + 8)) "$x" "$hr" -C GRAY5
		ci=$((ci + 1))
	done
	draw_now_mark
}

# "acum" over the chart where the current time falls (by the minute: at 14:20, a third into
# the 14:00 bar): a black arrowhead (ui/acum.png) under the word, and a dotted line from it
# down to the top of that hour's bar. The chart starts at the hour of the last download.
draw_now_mark() {
	set -- $(date '+%H %M')
	nm_h=${1#0} nm_m=${2#0}
	nm_f=${W_HOURS%%:*}
	nm_f=${nm_f#0}
	nm_o=$(((${nm_h:-0} - ${nm_f:-0} + 24) % 24))
	[ "$nm_o" -lt "$cn" ] || return 0
	nm_x=$((cl + nm_o * pitch + ${nm_m:-0} * pitch / 60))
	fb_image "$DIR/ui/acum.png" $((nm_x - 8)) $((ct - 8)) 16 11
	fb_ctext "$F_BOLD" 15 $((ct - 25)) "$nm_x" "$T_NOWMARK" -O
	nm_p=$(echo $W_PROBS | cut -d' ' -f$((nm_o + 1)))
	nm_bh=$((${nm_p:-0} * ch / 100))
	[ "$nm_bh" -lt 4 ] && nm_bh=4
	nm_end=$((ct + ch - nm_bh - 2))
	nm_y=$((ct + 6))
	while [ "$nm_y" -lt "$nm_end" ]; do
		nm_l=6
		[ $((nm_y + nm_l)) -gt "$nm_end" ] && nm_l=$((nm_end - nm_y))
		fb_rect "$nm_y" $((nm_x - 1)) 2 "$nm_l" BLACK
		nm_y=$((nm_y + 10))
	done
}

# Legend under the precipitation title (only when snow is due): draw_legend LEFT TOP
draw_legend() {
	lx=$1
	for it in "GRAY5|$T_LEGSNOW" "BLACK|$T_LEGRAIN" "GRAYA|$T_LEGDRY"; do
		fb_rect "$2" "$lx" 16 16 "${it%%|*}"
		fb_ltext "$F_REG" 20 $(($2 - 2)) $((lx + 23)) "${it#*|}" -C GRAY5
		lx=$((lx + 23 + $(tw_c "$F_REG" 20 "${it#*|}") + 22))
	done
}

# Precipitation box (frame and black header are in the chrome): title, window, peak, chart.
# draw_precip_box LEFT TOP WIDTH HEIGHT HEADER
draw_precip_box() {
	pl=$1 pt=$2 pw=$3 ph=$4 phd=$5
	if [ "$PREC_SNOW" = 1 ]; then pk=$T_SNOWUP; else pk=$T_RAINUP; fi
	fb_head "$pt" "$phd" $((pl + pw / 2)) $((pw - 40)) "$pk · $T_NEXT12"
	pleg=0
	case " $W_SNOWY " in *" 1 "*) pleg=1 ;; esac
	if [ "$ORIENT" = landscape ]; then
		fb_ltext "$F_BOLD" 31 $((pt + 66)) $((pl + 21)) "$rain_text"
		fb_ltext "$F_REG" 26 $((pt + 70)) $((pl + 27 + $(tw_c "$F_BOLD" 31 "$rain_text"))) "$T_MAX $W_RAIN_MAXP%" -C GRAY5
		if [ "$pleg" = 1 ]; then
			draw_legend $((pl + 21)) $((pt + 112))
			draw_precip_chart $((pl + 18)) $((pw - 36)) $((pt + 162)) $((ph - 230))
		else
			draw_precip_chart $((pl + 18)) $((pw - 36)) $((pt + 120)) $((ph - 188))
		fi
	else
		fb_ltext "$F_BOLD" 36 $((pt + 63)) $((pl + 22)) "$rain_text"
		fb_rtext "$F_REG" 29 $((pt + 68)) $((pl + pw - 20)) "$T_MAX $W_RAIN_MAXP%" -C GRAY5
		if [ "$pleg" = 1 ]; then
			draw_legend $((pl + 20)) $((pt + 108))
			draw_precip_chart $((pl + 16)) $((pw - 34)) $((pt + 140)) $((ph - 186))
		else
			draw_precip_chart $((pl + 16)) $((pw - 34)) $((pt + 120)) $((ph - 166))
		fi
	fi
}

# Day N of the forecast (1 = tomorrow): sets D_WD D_DATE D_HI D_LO D_POP and ICON DESC.
day_data() {
	D_WD=$(nth "$1" "$W_D_DAYS")
	D_DATE=$(nth "$1" "$W_D_DATES")
	D_HI=$(tconv "$(nth "$1" "$W_D_MAX")")
	D_LO=$(tconv "$(nth "$1" "$W_D_MIN")")
	D_POP=$(nth "$1" "$W_D_POP")
	describe "$(nth "$1" "$W_D_CODES")" 1
}

# Portrait card for tomorrow / the day after: title, icon, big high, gray "/ low", description.
# draw_day_card LEFT DAY TITLE
draw_day_card() {
	day_data "$2"
	[ -n "$D_WD" ] || return 0
	dc=$(($1 + 165))
	fb_head 574 52 "$dc" 290 "$3"
	dh="$D_HI°" dlo="/ $D_LO°"
	# High at 93 px, low at half that; both shrink together when "-8° / -15°" would not fit.
	dhp=93
	while :; do
		dlp=$((dhp / 2))
		dwh=$(tw_c "$F_BOLD" "$dhp" "$dh")
		dwl=$(tw_c "$F_REG" "$dlp" "$dlo")
		[ $((84 + dwh + 4 + dwl)) -le 311 ] || [ "$dhp" -lt 50 ] && break
		dhp=$((dhp * 94 / 100))
	done
	dgx=$(($1 + (331 - 84 - dwh - 4 - dwl) / 2))
	[ "$dgx" -lt $(($1 + 8)) ] && dgx=$(($1 + 8))
	draw_icon $((dgx - 10)) 641 92
	# Same baseline as at full size (ascent 0.81 of the size).
	fb_ltext "$F_BOLD" "$dhp" $((625 + (93 - dhp) * 81 / 100)) $((dgx + 84)) "$dh" -O
	fb_ltext "$F_REG" "$dlp" $((664 + (47 - dlp) * 81 / 100)) $((dgx + 84 + dwh + 4)) "$dlo" -O -C GRAY5
	fb_ctext "$F_REG" 30 734 "$dc" "$DESC" -O
}

# Columns of a day box: draw_day_cols FIRST_DAY LEFT COL_WIDTH HEAD_TOP ICON_TOP ICON TEMP_TOP TEMP_PX
# HEAD_HEIGHT
draw_day_cols() {
	dk=0
	while [ "$dk" -lt 3 ]; do
		day_data $(($1 + dk))
		[ -n "$D_WD" ] || break
		dcx=$(($2 + dk * $3 + $3 / 2))
		fb_head "$4" "$9" "$dcx" $(($3 - 40)) "$(wd_upper "$D_WD")"
		draw_icon $((dcx - $6 / 2)) "$5" "$6"
		dtp=$(fit_px "$F_BOLD" "$8" $(($3 - 26)) "$D_HI° / $D_LO°")
		fb_ctext "$F_BOLD" "$dtp" $(($7 + ($8 - dtp) * 6 / 10)) "$dcx" "$D_HI° / $D_LO°" -O
		dk=$((dk + 1))
	done
}

# Capsules for the next three days (simple view without precipitation): weekday and date, icon,
# high / low, description and the chance of rain.
# draw_capsules LEFT PITCH WIDTH TOP TITLE_PX ICON_TOP ICON TEMP_TOP TEMP_PX DESC_TOP DESC_PX POP_TOP POP_PX
draw_capsules() {
	ck=0
	while [ "$ck" -lt 3 ]; do
		day_data $((ck + 1))
		[ -n "$D_WD" ] || break
		ccx=$(($1 + ck * $2 + $3 / 2))
		fb_head "$4" "$5" "$ccx" $(($3 - 28)) "$(wd_upper "$D_WD") $D_DATE"
		draw_icon $((ccx - $7 / 2)) "$6" "$7"
		ctp=$(fit_px "$F_BOLD" "$9" $(($3 - 14)) "$D_HI° / $D_LO°")
		fb_ctext "$F_BOLD" "$ctp" $(($8 + ($9 - ctp) * 6 / 10)) "$ccx" "$D_HI° / $D_LO°" -O
		cdp=$(fit_px "$F_REG" "${11}" $(($3 - 12)) "$DESC")
		fb_ctext "$F_REG" "$cdp" "${10}" "$ccx" "$DESC" -O
		fb_ctext "$F_REG" "${13}" "${12}" "$ccx" "$T_POP $D_POP%" -O -C GRAY5
		ck=$((ck + 1))
	done
}

# Scale of N boxes, the first FILLED black: draw_scale LEFT TOP N FILLED BOX_W
draw_scale() {
	sk=0
	while [ "$sk" -lt "$3" ]; do
		sx=$(($1 + sk * ($5 + 4)))
		fb_rect "$2" "$sx" "$5" 10 BLACK
		[ "$sk" -ge "$4" ] && fb_rect $(($2 + 2)) $((sx + 2)) $(($5 - 4)) 6 WHITE
		sk=$((sk + 1))
	done
}

# Time of day in the chosen clock format ("07:42" or "7:42 AM").
clock_fmt() {
	if [ "$CLK12" = 1 ] && [ -n "$1" ]; then
		echo "$1" | awk -F: '{ h = $1 + 0; s = (h < 12) ? "AM" : "PM"; h = h % 12; if (h == 0) h = 12; printf "%d:%s %s", h, $2, s }'
	else
		echo "${1:-–}"
	fi
}

# Landscape capsule with the sun, the UV index and pollen (frame and header in the chrome).
draw_sun_box() {
	# One size for the three titles: the one that fits the longest.
	sb_p=31
	for sb_t in "$T_SUN" "$T_UV" "$T_POLLEN"; do sb_p=$(fit_px "$F_BOLD" "$sb_p" 129 "$sb_t"); done
	fb_head 458 46 590 130 "$T_SUN" "$sb_p"
	fb_head 458 46 750 130 "$T_UV" "$sb_p"
	fb_head 458 46 910 130 "$T_POLLEN" "$sb_p"
	fb_ctext "$F_REG" 20 512 590 "$T_SUNRISE"
	fb_ctext "$F_BOLD" 29 536 590 "$(clock_fmt "$W_SUNRISE")"
	fb_ctext "$F_REG" 20 579 590 "$T_SUNSET"
	fb_ctext "$F_BOLD" 29 603 590 "$(clock_fmt "$W_SUNSET")"
	if [ -n "$W_UV" ]; then
		if [ "$W_UV" -le 2 ]; then uvl=1; elif [ "$W_UV" -le 5 ]; then uvl=2
		elif [ "$W_UV" -le 7 ]; then uvl=3; elif [ "$W_UV" -le 10 ]; then uvl=4; else uvl=5; fi
		fb_ctext "$F_BOLD" 74 511 750 "$W_UV"
		fb_ctext "$F_REG" 22 586 750 "$(echo "$T_UVLV" | cut -d'|' -f"$uvl")"
		draw_scale 690 620 5 "$uvl" 21
	else
		fb_ctext "$F_BOLD" 74 511 750 "–"
		draw_scale 690 620 5 0 21
	fi
	POLLEN_LVL=0 POLLEN_PLANT=""
	[ -f "$POLLEN_ENV" ] && . "$POLLEN_ENV"
	if [ "${POLLEN_LVL:-0}" -gt 0 ]; then
		fb_ctext "$F_BOLD" 29 520 910 "$(echo "$T_POLLV" | cut -d'|' -f"$POLLEN_LVL")"
		pp=$T_NOPOLLEN
		[ -n "$POLLEN_PLANT" ] && pp=$(plant_name "$POLLEN_PLANT")
		fb_ctext "$F_REG" 22 561 910 "$pp"
	else
		fb_ctext "$F_BOLD" 29 520 910 "–"
		fb_ctext "$F_REG" 22 561 910 "$T_NODATA2"
	fi
	draw_scale 850 620 4 "${POLLEN_LVL:-0}" 27
}

plant_name() {
	if [ "$UI_LANG" = en ]; then
		case $1 in grass) echo grasses ;; *) echo "$1" ;; esac
		return 0
	fi
	case $1 in
	alder) echo arin ;; birch) echo mesteacăn ;; olive) echo măslin ;;
	grass) echo graminee ;; mugwort) echo pelin ;; ragweed) echo ambrozie ;; *) echo "$1" ;;
	esac
}

# Portrait screen: header, current weather and warnings, then (5-day view) two day cards and a
# box with three more days, or (simple view) the precipitation box when some is due, else
# capsules for the next three days.
# Gray dots in the left margin, growing toward the top, over the height of the light swipe
# zone (ui/glisare-p.png, glisare-l.png: 40 px wide).
draw_swipe_dots() {
	[ "${LIGHT_SWIPE:-1}" = 1 ] || return 0
	if [ "$ORIENT" = landscape ]; then sd=l; else sd=p; fi
	fb_image "$DIR/ui/glisare-$sd.png" 0 "$SW_TOP" 40 $((SW_BOT - SW_TOP))
}

draw_portrait() {
	if [ -z "$ST_FETCHED" ]; then chrome=p-antet
	elif [ "$LAYOUT" = weather ]; then chrome=p-5zile
	elif [ -n "$rain_text" ]; then chrome=p-ploaie
	else chrome=p-simplu; fi
	draw_chrome "$chrome"
	draw_swipe_dots
	draw_clock
	draw_date
	if [ -z "$ST_FETCHED" ]; then
		fb_rect 102 40 678 2 BLACK
		fb_text "$F_BOLD" 40 300 0 0 "$T_LOADING"
		return 0
	fi
	cpx=$(fit_px "$F_BOLD" $TXT_CITY 340 "$CITY_LABEL")
	fb_ltext "$F_BOLD" "$cpx" 116 40 "$CITY_LABEL"
	fy=494
	[ "$chrome" = p-simplu ] && fy=511
	draw_warnings
	# Line under the clock, up to the first warning box (which touches it).
	fb_rect 102 40 $((HDR_END - 40)) 2 BLACK
	if [ "$WARN_SHOWN" = 0 ]; then
		# No codes: temperature in the left half, icon in the right half of the free area.
		draw_now_side 40 104 718 $((fy + 4))
	else
		draw_temp 40 477 252 405
		# Icon centred on the digits (vertically) and in the space right of the temperature.
		# The icon file's white square stays under the warning texts (IC_TOP).
		IC_LEFT=$((TEMP_END + 2)) IC_RIGHT=748 IC_PCT=100 IC_TOP=$((WARN_BOT + 4)) IC_FIT=1 IC_BOT=$((fy - 6))
		draw_icon_c $(((TEMP_END + 718) / 2)) $((477 - t_p * 32 / 100)) 260 $((477 - t_p * 32 / 100 - WARN_BOT - 10)) $((718 - TEMP_END - 16))
		IC_TOP=0 IC_FIT=0
	fi
	# The description and the wind go right, under the temperature (with or without codes).
	dpx=$(fit_px "$F_BOLD" 39 330 "$NOW_DESC")
	fb_rtext "$F_BOLD" "$dpx" "$fy" 712 "$NOW_DESC"
	[ -n "$wind" ] && fb_rtext "$F_REG" $TXT_INFO $((fy + 40)) 712 "$wind"
	[ -n "$feels" ] && fb_ltext "$F_REG" $TXT_INFO $((fy + 7)) 40 "$feels"
	[ -n "$hilo" ] && fb_ltext "$F_REG" $TXT_INFO $((fy + 40)) 40 "$hilo"
	case $chrome in
	p-5zile)
		draw_day_card 40 1 "$T_DAY1"
		draw_day_card 387 2 "$T_DAY2"
		draw_day_cols 3 32 231 788 838 56 892 38 44
		;;
	p-ploaie)
		draw_precip_box 40 574 678 364 46
		;;
	*)
		draw_capsules 40 231 215 616 44 668 98 776 41 838 26 873 23
		;;
	esac
}

# Landscape screen: the current weather in a framed panel on the left (warnings at its top); on
# the right the clock, then the day cards, the precipitation box or the day capsules with the
# sun / UV / pollen box.
draw_landscape() {
	if [ -z "$ST_FETCHED" ]; then chrome=l-antet
	elif [ "$LAYOUT" = weather ]; then chrome=l-5zile
	elif [ -n "$rain_text" ]; then chrome=l-ploaie
	else chrome=l-simplu; fi
	draw_chrome "$chrome"
	draw_swipe_dots
	draw_clock
	draw_date
	if [ -z "$ST_FETCHED" ]; then
		fb_text "$F_BOLD" 36 360 40 524 "$T_LOADING"
		return 0
	fi
	draw_warnings
	if [ "$WARN_SHOWN" = 0 ]; then
		# No codes: icon and temperature centred in the two halves of the panel above the
		# texts.
		draw_now_split 270 57 488 430 82 67
	else
		draw_temp 54 466 172 259
		ic_cy=$((466 - t_p * 32 / 100))
		ic_hh=$((488 - ic_cy))
		[ $((ic_cy - WARN_BOT - 10)) -lt "$ic_hh" ] && ic_hh=$((ic_cy - WARN_BOT - 10))
		# 97%: at full size the sun's rays touched the "C".
		IC_LEFT=$((TEMP_END + 2)) IC_RIGHT=496 IC_PCT=97 IC_TOP=$((WARN_BOT + 4)) IC_FIT=1 IC_BOT=484
		draw_icon_c $(((TEMP_END + 490) / 2)) "$ic_cy" 200 "$ic_hh" $((490 - TEMP_END - 12))
		IC_TOP=0 IC_FIT=0
	fi
	# Under the description: "Resimțit", max / min, wind; then the city.
	dpx=$(fit_px "$F_BOLD" 42 420 "$NOW_DESC")
	fb_ltext "$F_BOLD" "$dpx" 490 59 "$NOW_DESC"
	[ -n "$feels" ] && fb_ltext "$F_REG" $TXT_INFO 540 59 "$feels"
	[ -n "$hilo" ] && fb_ltext "$F_REG" $TXT_INFO 578 59 "$hilo"
	[ -n "$wind" ] && fb_ltext "$F_REG" $TXT_INFO 616 59 "$wind"
	cpx=$(fit_px "$F_BOLD" $TXT_CITY 420 "$CITY_LABEL")
	fb_ltext "$F_BOLD" "$cpx" 664 57 "$CITY_LABEL"
	case $chrome in
	l-5zile)
		for lc in "516|1|$T_DAY1" "758|2|$T_DAY2"; do
			lx=${lc%%|*} lr=${lc#*|}
			day_data "${lr%%|*}"
			[ -n "$D_WD" ] || continue
			fb_head 156 48 $((lx + 113)) 190 "${lr#*|}"
			draw_icon $((lx + 113 - 55)) 214 110
			ltp=$(fit_px "$F_BOLD" 50 210 "$D_HI° / $D_LO°")
			fb_ctext "$F_BOLD" "$ltp" $((332 + (50 - ltp) * 6 / 10)) $((lx + 113)) "$D_HI° / $D_LO°" -O
		done
		draw_day_cols 3 510 160 416 488 82 606 36 46
		;;
	l-ploaie)
		draw_precip_box 516 156 468 506 46
		;;
	*)
		draw_capsules 516 160 148 156 46 216 86 311 31 357 22 391 21
		draw_sun_box
		;;
	esac
}

# Status inputs: battery level, charging, weather fetch time and whether it is stale.
# Sources $WEATHER_ENV. STATUS_KEY changes exactly when the status texts would look different.
read_status() {
	ST_FETCHED="" ST_OFFLINE=0
	if [ -f "$WEATHER_ENV" ]; then
		. "$WEATHER_ENV"
		ST_FETCHED=$W_FETCHED
		# Stale after two missed fetches (plus 5 minutes of slack).
		[ $(($(date +%s) - W_FETCHED)) -gt $(($(weather_minutes) * 120 + 300)) ] && ST_OFFLINE=1
	fi
	ST_LVL=$(lipc-get-prop com.lab126.powerd battLevel 2>/dev/null)
	ST_CHG=$(lipc-get-prop com.lab126.powerd isCharging 2>/dev/null)
	ST_BUSY=0
	[ -f "$STATE/fetching" ] && ST_BUSY=1
	STATUS_KEY="$ST_LVL $ST_CHG $ST_FETCHED $ST_OFFLINE $ST_BUSY"
}

# Battery (black glyph, bold percentage, "Se încarcă" / "Încarcă bateria" in bold) ending at
# BAT_R, and the "actualizat 14:15" text (black and bold, "! fără date din", when stale).
# Portrait: both in the footer; landscape: the update time under the divider, top right.
draw_status() {
	DRAWN_STATUS=$STATUS_KEY
	bat_left=$BAT_R
	if [ -n "$ST_LVL" ]; then
		gx=$((BAT_R - 44)) gy=$BAT_Y
		fill=$((ST_LVL * 30 / 100))
		[ "$fill" -lt 2 ] && fill=2
		fb_rect "$gy" "$gx" 40 20 BLACK
		fb_rect $((gy + 2)) $((gx + 2)) 36 16 WHITE
		fb_rect $((gy + 5)) $((gx + 5)) "$fill" 10 BLACK
		fb_rect $((gy + 6)) $((gx + 40)) 4 8 BLACK
		fb_rtext "$F_BOLD" 26 $((gy - 4)) $((gx - 7)) "$ST_LVL%"
		bat_left=$RTEXT_LEFT
		msg=""
		if [ "$ST_CHG" = 1 ]; then
			fb_image "$DIR/icons/bolt.png" $((bat_left - 16)) $((gy + 2)) 11 17
			bat_left=$((bat_left - 16))
			msg=$T_CHARGING
		elif [ "$ST_LVL" -lt "${BATT_LOW:-25}" ]; then
			msg=$T_CHARGEME
		fi
		if [ -n "$msg" ]; then
			# Both messages are drawn in the cleared status zone (ST1), smaller if needed.
			set -- $ST1
			mpx=$(fit_px "$F_BOLD" 26 $((bat_left - 10 - $2 - 4)) "$msg")
			fb_rtext "$F_BOLD" "$mpx" $((gy - 4 + (26 - mpx) * 81 / 100)) $((bat_left - 10)) "$msg"
			bat_left=$RTEXT_LEFT
		fi
	fi
	font=$F_REG color=GRAY5 upd=""
	if [ "$ST_BUSY" = 1 ]; then
		upd=$T_UPDATING
	elif [ -n "$ST_FETCHED" ]; then
		when=$(date -d "@$ST_FETCHED" '+%H:%M' 2>/dev/null)
		[ "$CLK12" = 1 ] && when=$(clock_fmt "$when")
		upd="$T_UPDATED $when"
		if [ "$ST_OFFLINE" = 1 ]; then
			font=$F_BOLD color=BLACK upd="! $T_NODATA $when"
		fi
	fi
	[ -n "$upd" ] || return 0
	if [ "$ORIENT" = landscape ]; then
		fb_rtext "$font" 27 "$UPD_Y" "$UPD_R" "$upd" -C "$color"
	else
		upx=$(fit_px "$font" 27 $((bat_left - UPD_L - 14)) "$upd")
		fb_ltext "$font" "$upx" "$UPD_Y" "$UPD_L" "$upd" -C "$color"
	fi
}

# Geometry (canvas units) of the parts redrawn on their own: the clock band, the status texts,
# the pop-ups, the buttons and the light swipe zone.
set_bands() {
	BTN=64
	if [ "$ORIENT" = landscape ]; then
		CLK_PX=58 CLOCK_TOP=18 CLK_R=826 CLK_L=560 CLOCK_H=58 DATE_Y=74 DATE_R=825
		B_MENU="846 680" B_LIGHT="846 24" B_EXIT="920 24" B_CITY="920 680"
		MENU_X=604 MENU_Y=282 B_LIGHT_R=984
		# Menu tip: points down at the ☰ button.
		MENU_TIP="866 $((282 + 378 - 2)) jos"
		WARN_L=54 WARN_Y=68 WARN_LW=330
		BAT_R=836 BAT_Y=702 UPD_R=984 UPD_Y=111
		# ST1 reaches the left edge of the right column, so the longest battery message
		# ("Încarcă bateria") is wiped too when it changes.
		ST1="694 516 320 40" ST2="108 520 464 32"
		SW_TOP=60 SW_BOT=700
	else
		CLK_PX=50 CLOCK_TOP=17 CLK_R=561 CLK_L=330 CLOCK_H=50 DATE_Y=71 DATE_R=567
		B_MENU="40 24" B_LIGHT="580 24" B_EXIT="654 24" B_CITY="40 944"
		MENU_X=40 MENU_Y=104 B_LIGHT_R=718
		# Menu tip: points up at the ☰ button.
		MENU_TIP="60 92 sus"
		WARN_R=718 WARN_Y=102 WARN_LW=330
		BAT_R=718 BAT_Y=966 UPD_L=123 UPD_Y=970
		ST1="958 110 608 44" ST2=""
		SW_TOP=110 SW_BOT=930
	fi
	MENU_W=380 MENU_H=378 LP_W=340 LP_H=150
	# Light bubble: right-aligned under the light button (its tip 222 px in, on the button).
	LP_X=$((B_LIGHT_R - LP_W)) LP_Y=98
}

# Redraw and refresh only the status texts, and only when they changed.
refresh_status() {
	# A pop-up may cover the status texts; closing it redraws the whole screen anyway.
	[ -f "$STATE/menu" ] && return 0
	read_status
	[ "$STATUS_KEY" = "$DRAWN_STATUS" ] && return 0
	for rs in "$ST1" "$ST2"; do
		[ -n "$rs" ] || continue
		set -- $rs
		fb_rect "$1" "$2" "$3" "$4" WHITE
	done
	draw_status
	for rs in "$ST1" "$ST2"; do
		[ -n "$rs" ] || continue
		set -- $rs
		fb_refresh "$1" "$2" "$3" "$4"
	done
}

# Minute tick between full redraws: clear, redraw and refresh only the clock band, and the
# status texts only when they changed; the rest of the screen is not touched.
draw_partial() {
	fb_rect "$CLOCK_TOP" "$CLK_L" $((CLK_R - CLK_L + 4)) "$CLOCK_H" WHITE
	draw_clock
	fb_refresh "$CLOCK_TOP" "$CLK_L" $((CLK_R - CLK_L + 4)) "$CLOCK_H"
	refresh_status
}

# Current-weather strings shared by the layouts: ICON, NOW_DESC, hilo, feels, wind, rain_text,
# PREC_SNOW (1 when the precipitation due is mostly snow) and CITY_LABEL.
prepare_now() {
	describe "$W_CODE" "$W_IS_DAY"
	NOW_DESC=$DESC NOW_ICON=$ICON
	hilo=""
	[ -n "$W_TMAX" ] && [ -n "$W_TMIN" ] && hilo="$T_HI $(tconv "$W_TMAX")° / $T_LO $(tconv "$W_TMIN")°"
	# "Resimțit 17°" and "Vânt 14 km/h" (mph with °F).
	feels="" wind=""
	if [ "${SHOW_FEELS:-1}" = 1 ]; then
		[ -n "$W_FEELS" ] && feels="$T_FEELS $(tconv "$W_FEELS")°"
		if [ -n "$W_WIND" ]; then
			if [ "$UNIT_T" = F ]; then
				wind="$T_WIND $(round "$(awk -v w="$W_WIND" 'BEGIN { print w * 0.621371 }')") mph"
			else
				wind="$T_WIND $(round "$W_WIND") km/h"
			fi
		fi
	fi
	# In capitals, like the box titles: "RESIMȚIT -7°", "MAX -1° / MIN -6°", "VÂNT 14 KM/H".
	feels=$(upper "$feels") hilo=$(upper "$hilo") wind=$(upper "$wind")
	CITY_LABEL=$(city_label)

	# Precipitation text when it is falling or expected within the lookahead window; snow when
	# it is snowing now or most of the wet hours bring snow.
	PREC_SNOW=${W_SNOW_MAJ:-0}
	if [ -n "$WET_NOW" ] || awk -v p="$W_PRECIP" 'BEGIN { exit !(p > 0) }'; then
		word=$T_RAINW
		if [ "$WET_NOW" = "Snowing now" ]; then word=$T_SNOWW PREC_SNOW=1; fi
		if [ -n "$W_RAIN_END" ] && [ "$W_RAIN_AT" = "${W_HOURS%% *}" ]; then
			rain_text="$word $T_UNTIL $W_RAIN_END"
		else
			rain_text="$word $T_NOW"
		fi
	else
		if [ "$PREC_SNOW" = 1 ]; then word=$T_SNOW wfrom=$T_SNOWFROM; else word=$T_RAIN wfrom=$T_RAINFROM; fi
		if [ -n "$W_RAIN_AT" ] && [ -n "$W_RAIN_END" ]; then
			rain_text="$word $W_RAIN_AT–$W_RAIN_END"
		elif [ -n "$W_RAIN_AT" ]; then
			rain_text="$wfrom $W_RAIN_AT"
		else
			rain_text=""
		fi
	fi
	ICON=$NOW_ICON
}

# draw FLASH: redraw and refresh the whole screen (FLASH=1: black flash, clears ghosting).
draw() {
	flash=$1
	draw_base
	finish_draw
}

# The whole screen into the framebuffer, without refreshing it (draw, and under the city picker).
draw_base() {
	touch "$STATE/drawing"
	read_status
	fbink -q -b -k >/dev/null 2>&1
	if [ -n "$ST_FETCHED" ]; then
		prepare_now
	fi
	if [ "$ORIENT" = landscape ]; then draw_landscape; else draw_portrait; fi
}

# Status, then push everything to the screen (FLASH=1: black flash against ghosting).
finish_draw() {
	draw_status
	# The city picker opened while this screen was being drawn: put it back on top.
	[ -f "$STATE/picker" ] && draw_picker
	# So did a pop-up: draw it again (2.06 dropped its state here, so a ☰ menu opened during a
	# redraw stayed on screen but ignored taps). The screen saved under it is older than this
	# one, so closing it redraws instead.
	case $(cut -d' ' -f1 "$STATE/menu" 2>/dev/null) in
	main)
		rm -f "$STATE/under.fb"
		draw_menu
		;;
	light)
		rm -f "$STATE/under.fb"
		draw_light_popup
		;;
	esac
	if [ "$flash" = 1 ]; then
		fbink -q -f -s >/dev/null 2>&1
	else
		fbink -q -s >/dev/null 2>&1
	fi
	rm -f "$STATE/drawing"
}

# --- Menu and light pop-up -----------------------------------------------------
# One pop-up at a time; $STATE/menu holds "main TOKEN" or "light TOKEN". Each closes by itself
# (MENU_SECONDS / LIGHT_SECONDS after the last tap or swipe); closing puts back the screen
# saved under it (fb_save / fb_restore).

# Rows of the ☰ menu, by id: o orientation, v view, f flip, r refresh, t °C/°F, c 12h/24h,
# l language. The first four are in the order last used (like the favourite cities), from
# o v f r at each start ($STATE/menuorder); t c l stay at the bottom.
menu_ids() {
	mi=$(cat "$STATE/menuorder" 2>/dev/null)
	echo "${mi:-o v f r} t c l"
}

# menu_used ID: one of the first four goes to the top.
menu_used() {
	case $1 in o | v | f | r) ;; *) return 0 ;; esac
	mu=$1
	for mi in $(menu_ids); do
		case $mi in "$1" | t | c | l) ;; *) mu="$mu $mi" ;; esac
	done
	echo "$mu" >"$STATE/menuorder"
}

menu_labels() {
	# Each row names the choice a tap switches to, not the current one.
	if [ "$LAYOUT" = weather ]; then ml_v=$T_V_SIMPLE; else ml_v=$T_V_LIST; fi
	if [ "$ORIENT" = landscape ]; then ml_o=$T_O_P; else ml_o=$T_O_L; fi
	if [ "$CLK12" = 1 ]; then ml_c=24h; else ml_c=12h; fi
	if [ "$UNIT_T" = F ]; then ml_t=C; else ml_t=F; fi
	ml_out=""
	for mi in $(menu_ids); do
		case $mi in
		o) ml="$T_M_ORIENT $ml_o" ;;
		v) ml="$T_M_VIEW $ml_v" ;;
		f) ml=$T_M_FLIP ;;
		r) ml=$T_M_REFRESH ;;
		t) ml="$T_M_TEMP °$ml_t" ;;
		c) ml="$T_M_CLOCK $ml_c" ;;
		*) ml=$T_M_LANG ;;
		esac
		ml_out="$ml_out${ml_out:+|}$ml"
	done
	echo "$ml_out"
}

# Speech bubble like the light panel: the tip (drawn after the box, over its outline) points
# at the ☰ button.
draw_menu() {
	fb_image "$DIR/ui/meniu.png" "$MENU_X" "$MENU_Y" "$MENU_W" "$MENU_H"
	set -- $MENU_TIP
	fb_image "$DIR/ui/varf-$3.png" "$1" "$2" 24 14
	mrow=0
	# Labels first: menu_labels splits on spaces, so not under IFS='|'.
	dm_l=$(menu_labels)
	IFS='|'
	set -- $dm_l
	unset IFS
	for ml in "$@"; do
		fb_ltext "$F_REG" 28 $((MENU_Y + mrow * 54 + 9)) $((MENU_X + 22)) "$ml" -O
		mrow=$((mrow + 1))
	done
	fb_refresh $((MENU_Y - 12)) "$MENU_X" "$MENU_W" $((MENU_H + 24))
}

light_level_now() {
	lipc-get-prop com.lab126.powerd flIntensity 2>/dev/null
}

# Light pop-up (light button): a small bubble under the button that says the light is set by
# swiping on the left edge, and, over the swipe dots, a bar of 24 steps like the Kobo Libra 2's
# (ui/lumina-bara-p.png / -l.png) with a black arrow at the current step. Closing the pop-up
# puts the dots back.
draw_light_info() {
	lcur=${1:-$(light_level_now)}
	lcur=${lcur:-0}
	if [ "$lcur" = 0 ]; then lname=$T_LIGHTOFF; else lname="$T_LIGHTT $lcur / 24"; fi
	fb_rect $((LP_Y + 14)) $((LP_X + 10)) $((LP_W - 20)) 44 WHITE
	fb_ltext "$F_BOLD" 32 $((LP_Y + 16)) $((LP_X + 22)) "$lname" -O
}

draw_light_popup() {
	fb_image "$DIR/ui/lumina-info.png" "$LP_X" "$LP_Y" "$LP_W" "$LP_H"
	fb_image "$DIR/ui/varf-sus.png" $((LP_X + 222)) $((LP_Y - 12)) 24 14
	lcur=$(light_level_now)
	draw_light_info "$lcur"
	lhp=$(fit_px "$F_REG" 26 $((LP_W - 44)) "$T_LIGHTH2")
	fb_ltext "$F_REG" "$lhp" $((LP_Y + 66)) $((LP_X + 22)) "$T_LIGHTH1" -O
	fb_ltext "$F_REG" "$lhp" $((LP_Y + 100)) $((LP_X + 22)) "$T_LIGHTH2" -O
	fb_refresh $((LP_Y - 12)) "$LP_X" "$LP_W" $((LP_H + 12))
	if [ "$ORIENT" = landscape ]; then sd=l; else sd=p; fi
	fb_rect "$SW_TOP" 0 40 $((SW_BOT - SW_TOP)) WHITE
	fb_image "$DIR/ui/lumina-bara-$sd.png" 0 "$SW_TOP" 40 $((SW_BOT - SW_TOP))
	draw_light_mark "$lcur"
	fb_refresh "$SW_TOP" 0 40 $((SW_BOT - SW_TOP))
}

# Arrow left of the bar at step N (0 = off: under the last step); the bar has 4 px of frame and
# 24 equal steps.
draw_light_mark() {
	lm_h=$(((SW_BOT - SW_TOP - 8) * 100 / 24))
	if [ "${1:-0}" -gt 0 ]; then
		lm_y=$((SW_BOT - 4 - ($1 * 100 - 50) * lm_h / 10000))
	else
		lm_y=$((SW_BOT - 4))
	fi
	fb_rect "$SW_TOP" 0 15 $((SW_BOT - SW_TOP)) WHITE
	fb_image "$DIR/ui/lumina-sageata.png" 1 $((lm_y - 11)) 13 22
}

# During a swipe with the light pop-up open: move the arrow and the step in the bubble.
light_live() {
	[ "$(cut -d' ' -f1 "$STATE/menu" 2>/dev/null)" = light ] || return 0
	draw_light_mark "$1"
	fb_refresh "$SW_TOP" 0 15 $((SW_BOT - SW_TOP))
	draw_light_info "$1"
	fb_refresh $((LP_Y + 14)) $((LP_X + 10)) $((LP_W - 20)) 44
}

# Frontlight presets (automatic light). Level 0 through powerd leaves the LEDs glowing faintly;
# "off" also writes 0 to the lamp driver's own node, which switches them off.
light_set() {
	case $1 in
	0)
		lipc-set-prop com.lab126.powerd flIntensity 0
		for n in /sys/class/backlight/*/brightness /sys/devices/system/fl_tps6116x/fl_tps6116x0/fl_intensity; do
			[ -w "$n" ] && echo 0 >"$n"
		done
		;;
	1)
		# 1 then 0: forces powerd to apply 0 even if it believes 0 is already set.
		lipc-set-prop com.lab126.powerd flIntensity 1
		lipc-set-prop com.lab126.powerd flIntensity 0
		;;
	2) lipc-set-prop com.lab126.powerd flIntensity "$LIGHT_1" ;;
	3) lipc-set-prop com.lab126.powerd flIntensity "$LIGHT_2" ;;
	*) lipc-set-prop com.lab126.powerd flIntensity "$LIGHT_3" ;;
	esac
	echo "$1" >"$STATE/lightidx"
	log "light $1: powerd $(light_level_now), nodes: $(for n in /sys/class/backlight/*/brightness /sys/devices/system/fl_tps6116x/fl_tps6116x0/fl_intensity; do [ -r "$n" ] && printf '%s=%s ' "$n" "$(cat "$n")"; done)"
}

# The screen under a pop-up is copied from the framebuffer before it opens, and copied back
# when it closes: the pop-up goes at once, with a flash against e-ink ghosts. (2.055 redrew the
# whole screen, which took seconds, so taps outside seemed to do nothing.) No copy while the
# main loop is drawing ($STATE/drawing): then closing redraws the screen as before.
FBDEV=${FBDEV:-/dev/fb0}
fb_save() {
	rm -f "$STATE/under.fb"
	[ -f "$STATE/drawing" ] && return 0
	cat "$FBDEV" >"$STATE/under.fb" 2>/dev/null || rm -f "$STATE/under.fb"
}

# Put the saved screen back (1 if there is none), then the clock is brought up to date.
fb_restore() {
	[ -s "$STATE/under.fb" ] && [ ! -f "$STATE/drawing" ] || return 1
	cat "$STATE/under.fb" >"$FBDEV" 2>/dev/null || return 1
	rm -f "$STATE/under.fb"
	fbink -q -f -s >/dev/null 2>&1
	touch "$STATE/clockdraw"
	kill -USR1 "$main_pid" 2>/dev/null
	return 0
}

# open_popup KIND SECONDS: draw the pop-up and close it after SECONDS without a tap (the
# screen is saved before the pressed button is drawn, see touch_watch).
open_popup() {
	op_tok="$1 $(date +%s)$$"
	echo "$op_tok" >"$STATE/menu"
	if [ "$1" = main ]; then draw_menu; else draw_light_popup; fi
	log "popup: $1 open"
	popup_timer "$2"
}

popup_timer() {
	pt_tok=$(cat "$STATE/menu" 2>/dev/null)
	(
		sleep "$1"
		[ "$(cat "$STATE/menu" 2>/dev/null)" = "$pt_tok" ] && close_popup
	) &
}

# The pop-ups cover part of the screen, so closing one redraws it without the pause of a layout
# change, with a flash: without one, e-ink ghosts of the pop-up stayed on the Kindle.
close_popup() {
	rm -f "$STATE/menu"
	fb_restore && return 0
	touch "$STATE/redraw"
	kill -USR1 "$main_pid" 2>/dev/null
}

# Tap outside the open pop-up (☰ menu or light bubble): the ☰ button again is ignored (a second
# tap there while it opened closed it again); the light button again switches the light pop-up
# off; elsewhere it closes, unless CLOSE_OUTSIDE=0.
tap_outside() {
	if on_btn "$1" && [ "$1" = "$B_LIGHT" ]; then
		log "popup: light button again, closed"
		close_popup
	elif on_btn "$1"; then
		log "popup: own button again, kept open"
	elif [ "${CLOSE_OUTSIDE:-1}" = 1 ]; then
		log "popup: tap outside, closed"
		close_popup
	fi
}

# press_btn KIND "X Y": a tapped button turns medium gray at once (ui/btn-KIND-apasat.png), so
# the tap is seen before what it opens is drawn. The next redraw of the screen restores it.
press_btn() {
	set -- "$1" $2
	fb_image "$DIR/ui/btn-$1-apasat.png" "$2" "$3" "$BTN" "$BTN"
	fb_refresh "$3" "$2" "$BTN" "$BTN"
}

# press_row N: row N of the ☰ menu turns medium gray (with its text) when tapped.
press_row() {
	pr_y=$((MENU_Y + $1 * 54 + 3))
	fb_rect "$pr_y" $((MENU_X + 6)) $((MENU_W - 12)) 48 GRAYA
	pr_t=$(menu_labels | cut -d'|' -f$(($1 + 1)))
	fb_ltext "$F_REG" 28 $((MENU_Y + $1 * 54 + 9)) $((MENU_X + 22)) "$pr_t" -O
	fb_refresh "$pr_y" "$MENU_X" "$MENU_W" 48
}

# --- City picker ------------------------------------------------------------
# cities.txt: county|town|latitude|longitude (county "*" = the first favourites). The chosen
# city is kept in city.sel (name|lat|lon) and survives restarts.
CITIES=$DIR/cities.txt
CITY_SEL=$DIR/city.sel
# The favourites row shows the last three cities chosen (name|lat|lon a line, the current
# one first, then the one before it, then the one before that).
RECENT=$DIR/recent.sel

load_city() {
	[ -f "$CITY_SEL" ] || return 0
	IFS='|' read -r c_n c_la c_lo <"$CITY_SEL"
	if [ -n "$c_n" ] && [ -n "$c_la" ] && [ -n "$c_lo" ]; then
		PLACE=$c_n LATITUDE=$c_la LONGITUDE=$c_lo
	fi
}

# First start: the current city, then the "*" lines of cities.txt (no repeats).
recent_init() {
	[ -s "$RECENT" ] && return 0
	{
		echo "$PLACE|$LATITUDE|$LONGITUDE"
		awk -F'|' '/^#/ || NF < 4 { next } $1 == "*" { print $2 "|" $3 "|" $4 }' "$CITIES"
	} | awk -F'|' 'NF >= 3 && $1 != "" && !seen[$1]++' | head -3 >"$RECENT.tmp" && mv "$RECENT.tmp" "$RECENT"
}

# recent_add NAME LAT LON: the city chosen goes first; if it was already in the list it moves
# up instead of being repeated; three are kept.
recent_add() {
	{
		echo "$1|$2|$3"
		[ -f "$RECENT" ] && awk -F'|' -v n="$1" 'NF >= 3 && $1 != n' "$RECENT"
	} | head -3 >"$RECENT.tmp" && mv "$RECENT.tmp" "$RECENT"
}

# The picker is a speech bubble over the screen, like the ☰ menu, pointing at the city button:
# a title row, 8 rows of three names and a nav row. Level 0: the favourites, then the counties
# in two tabs of similar size; level 1: the towns of a county (8 rows a page). The bubble keeps
# its height on every page, so turning a page only redraws the bubble, never the screen under it.
pk_geom() {
	PK_W=678 PK_TH=58 PK_RH=54 PK_NH=62 PK_COLW=218 PK_ROWS=8
	if [ "$ORIENT" = landscape ]; then
		PK_X=306 PK_BOT=668 PK_TIPX=940
	else
		PK_X=40 PK_BOT=932 PK_TIPX=60
	fi
	PK_H=$((PK_TH + PK_ROWS * PK_RH + PK_NH))
	PK_Y=$((PK_BOT - PK_H))
}

# Item list of a level into $STATE/pk_items: S|name|lat|lon picks a city, C|county opens a
# county. Level 0 lists the favourites first.
pk_build() {
	if [ "$1" = 0 ]; then
		recent_init
		awk -F'|' 'NF >= 3 { print "S|" $1 "|" $2 "|" $3 }' "$RECENT"
		awk -F'|' '/^#/ || NF < 4 { next } $1 != "*" && !seen[$1]++ { print "C|" $1 }' "$CITIES"
	else
		awk -F'|' -v c="$2" '/^#/ || NF < 4 { next } $1 == c { print "S|" $2 "|" $3 "|" $4 }' "$CITIES"
	fi >"$STATE/pk_items"
}

# Rows of the current page into $STATE/pk_page (one item per line, in reading order; on level
# 0 the first three are the favourites row) and PK_FAV (1 if row 0 holds the favourites),
# PK_PAGES. Fails when the picker was closed meanwhile.
pk_page() {
	pk_st=$(cat "$STATE/picker" 2>/dev/null)
	[ -n "$pk_st" ] || return 1
	IFS='|'
	set -- $pk_st
	unset IFS
	pk_lvl=$1 pk_cty=$2 pk_page=$3 pk_tok=$4
	if [ "$pk_lvl" = 0 ]; then
		grep '^S|' "$STATE/pk_items" | head -3 >"$STATE/pk_fav"
		grep '^C|' "$STATE/pk_items" >"$STATE/pk_cty"
		nc=$(wc -l <"$STATE/pk_cty")
		half=$(((nc + 1) / 2))
		PK_PAGES=2
		if [ "$pk_page" = 1 ]; then f=$((half + 1)) l=$nc; else f=1 l=$half; fi
		{
			cat "$STATE/pk_fav"
			k=$(wc -l <"$STATE/pk_fav")
			while [ "$k" -lt 3 ]; do echo "-|"; k=$((k + 1)); done
			sed -n "${f},${l}p" "$STATE/pk_cty"
		} >"$STATE/pk_page"
		PK_FAV=1
	else
		n=$(wc -l <"$STATE/pk_items")
		PK_PAGES=$(((n + 23) / 24))
		[ "$PK_PAGES" -lt 1 ] && PK_PAGES=1
		sed -n "$((pk_page * 24 + 1)),$((pk_page * 24 + 24))p" "$STATE/pk_items" >"$STATE/pk_page"
		PK_FAV=0
	fi
}

# Labels measured in one pass (one awk for all of them): lines "FONT|PX|MAXW|CX|TOP|H|TEXT" on
# stdin; each TEXT shrinks until it fits MAXW and is centred on CX (CX "L<x>": left edge at x)
# and in the TOP..TOP+H band.
ctext_rows() {
	awk -F'|' -v reg="${F_REG%.ttf}.wid" -v bold="${F_BOLD%.ttf}.wid" '
		# Keys are the font letter (r, b) followed by the character.
		function load(f, k,  l, sp, key) {
			while ((getline l < f) > 0) { sp = index(l, " "); key = k substr(l, sp + 1); w[key] = substr(l, 1, sp - 1) + 0 }
		}
		function width(k, px, s,  n, i, c, t) {
			n = length(s); t = 0
			for (i = 1; i <= n; ) {
				c = k substr(s, i, 3); if (c in w) { t += w[c]; i += 3; continue }
				c = k substr(s, i, 2); if (c in w) { t += w[c]; i += 2; continue }
				c = k substr(s, i, 1); t += (c in w) ? w[c] : 1100; i++
			}
			return int(t * px / 2288 + 0.5)
		}
		BEGIN { load(reg, "r"); load(bold, "b") }
		{
			k = (index($1, "Bold") > 0) ? "b" : "r"
			px = $2 + 0
			while (px > 14 && width(k, px, $7) > $3 + 0) px = int(px * 92 / 100)
			left = (substr($4, 1, 1) == "L") ? substr($4, 2) + 0 : $4 - int(width(k, px, $7) / 2)
			printf "%s|%d|%d|%d|%s\n", $1, px, left, $5 + int(($6 - px) / 2), $7
		}'
}

# Draw what ctext_rows printed (FONT|PX|LEFT|TOP|TEXT a line).
ctext_draw() {
	while IFS='|' read -r cd_f cd_p cd_l cd_t cd_s; do
		fb_ltext "$cd_f" "$cd_p" "$cd_t" "$cd_l" "$cd_s" -O
	done
}

# Draw the bubble over the screen and refresh it. The county and town rows come from
# ui/loc/<md5 of their names>.png (made by tools/make_ui.py from cities.txt); a page whose names
# changed since (cities.txt edited) is drawn name by name.
draw_picker() {
	pk_geom
	pk_page || return 0
	fb_image "$DIR/ui/loc-$PK_ROWS.png" "$PK_X" "$PK_Y" "$PK_W" "$PK_H"
	fb_image "$DIR/ui/varf-jos.png" "$PK_TIPX" $((PK_BOT - 2)) 24 14
	if [ "$pk_lvl" = 0 ]; then title="$T_PICK"; else title="$pk_cty · $T_PICKTOWN"; fi
	[ "$PK_PAGES" -gt 1 ] && title="$title · $((pk_page + 1))/$PK_PAGES"
	ny=$((PK_Y + PK_H - PK_NH))
	pk_nav
	sw=$((PK_W / 3))
	r0=$((PK_Y + PK_TH))
	sed -n "$((PK_FAV * 3 + 1)),\$p" "$STATE/pk_page" >"$STATE/pk_rest"
	nrest=$(wc -l <"$STATE/pk_rest")
	img=$DIR/ui/loc/$(cut -d'|' -f2 "$STATE/pk_rest" | md5sum 2>/dev/null | cut -c1-32).png
	[ "$nrest" -gt 0 ] && [ -f "$img" ] || img=""
	if [ -n "$img" ]; then
		fb_image "$img" $((PK_X + 12)) $((r0 + PK_FAV * PK_RH - 1)) 654 $((((nrest + 2) / 3) * PK_RH))
	fi
	# Row lines (only the favourites row, or every row when there is no image) and the line
	# above the nav row.
	if [ "$PK_FAV" = 1 ]; then fb_rect $((r0 - 1)) $((PK_X + 12)) $((PK_W - 24)) 2 GRAY9; fi
	if [ -z "$img" ]; then
		i=0
		while [ "$i" -lt "$nrest" ]; do
			fb_rect $((r0 + (PK_FAV + i / 3) * PK_RH - 1)) $((PK_X + 12)) $((PK_W - 24)) 2 GRAY9
			i=$((i + 3))
		done
	fi
	fb_rect $((ny - 1)) $((PK_X + 12)) $((PK_W - 24)) 2 GRAY9
	# All the texts: title, favourites (bold), names without an image, nav row.
	{
		echo "$F_BOLD|30|$((PK_W - 44))|L$((PK_X + 22))|$((PK_Y + 14))|30|$title"
		i=0
		while IFS='|' read -r typ name rest; do
			r=$((i / 3)) c=$((i % 3))
			if [ "$typ" != - ] && { [ "$r" -lt "$PK_FAV" ] || [ -z "$img" ]; }; then
				if [ "$r" -lt "$PK_FAV" ]; then lf=$F_BOLD; else lf=$F_REG; fi
				echo "$lf|27|$((PK_COLW - 12))|$((PK_X + 12 + c * PK_COLW + PK_COLW / 2))|$((r0 + r * PK_RH))|$PK_RH|$name"
			fi
			i=$((i + 1))
		done <"$STATE/pk_page"
		k=0
		for lab in "$PK_PREV" "$T_CLOSE" "$PK_NEXT"; do
			[ -n "$lab" ] && echo "$F_BOLD|26|$((sw - 16))|$((PK_X + k * sw + sw / 2))|$((ny - 2))|$PK_NH|$lab"
			k=$((k + 1))
		done
	} | ctext_rows >"$STATE/pk_text"
	ctext_draw <"$STATE/pk_text"
	fb_refresh "$PK_Y" "$PK_X" "$PK_W" $((PK_H + 14))
}

# Labels of the nav row for the current page (empty = no button).
pk_nav() {
	PK_PREV="" PK_NEXT=""
	if [ "$pk_lvl" = 1 ] || [ "$pk_page" -gt 0 ]; then PK_PREV=$T_BACK; fi
	[ "$pk_page" -lt $((PK_PAGES - 1)) ] && PK_NEXT=$T_NEXT
}

# picker_open LEVEL COUNTY PAGE: draw the bubble (in the touch process: taps that come while
# it is being drawn are not read, so a second tap cannot close it half drawn).
picker_open() {
	rm -f "$STATE/menu"
	tok=$(date +%s)
	echo "$1|$2|$3|$tok" >"$STATE/picker"
	pk_build "$1" "$2"
	log "picker: open level $1${2:+ ($2)} page $3"
	draw_picker
	# Idle timeout: the bubble closes after 60 s without a tap.
	(
		sleep 60
		[ "$(cut -d'|' -f4 "$STATE/picker" 2>/dev/null)" = "$tok" ] && close_picker timeout
	) &
}

# Closing redraws the whole screen with a flash (against e-ink ghosting).
close_picker() {
	rm -f "$STATE/picker"
	log "picker: close${1:+ ($1)}"
	# A city chosen redraws everything (new forecast); otherwise the saved screen goes back.
	if [ "$1" = chosen ]; then rm -f "$STATE/under.fb"; else fb_restore && return 0; fi
	touch "$STATE/redraw"
	kill -USR1 "$main_pid" 2>/dev/null
}

# press_cell TOP LEFT WIDTH HEIGHT FONT PX TEXT: a tapped cell turns medium gray (with its
# text) at once, before what it does is drawn.
press_cell() {
	fb_rect "$1" "$2" "$3" "$4" GRAYA
	echo "$5|$6|$(($3 - 8))|$(($2 + $3 / 2))|$1|$4|$7" | ctext_rows | ctext_draw
	fb_refresh "$1" "$2" "$3" "$4"
}

# Tap in the picker (canvas $1 $2); outside the bubble closes it, except on the city button
# (a second tap there while the bubble opens did close it in 2.052).
picker_tap() {
	pk_geom
	pk_page || return 0
	tx=$(($1 - PK_X)) ty=$(($2 - PK_Y))
	if [ "$tx" -lt 0 ] || [ "$tx" -ge "$PK_W" ] || [ "$ty" -lt 0 ] || [ "$ty" -ge "$PK_H" ]; then
		if on_btn "$B_CITY"; then
			log "picker: city button again, kept open"
		elif [ "${CLOSE_OUTSIDE:-1}" = 1 ]; then
			close_picker outside
		fi
		return 0
	fi
	if [ "$ty" -ge $((PK_H - PK_NH)) ]; then
		k=$((tx * 3 / PK_W))
		pk_nav
		sw=$((PK_W / 3))
		case $k in 0) lab=$PK_PREV ;; 1) lab=$T_CLOSE ;; *) lab=$PK_NEXT ;; esac
		[ -n "$lab" ] || return 0
		press_cell $((PK_Y + PK_H - PK_NH + 4)) $((PK_X + k * sw + 10)) $((sw - 20)) $((PK_NH - 12)) "$F_BOLD" 26 "$lab"
		case $k in
		0)
			if [ "$pk_page" -gt 0 ]; then picker_open "$pk_lvl" "$pk_cty" $((pk_page - 1))
			else picker_open 0 "" 0; fi
			;;
		1) close_picker ;;
		*) picker_open "$pk_lvl" "$pk_cty" $((pk_page + 1)) ;;
		esac
		return 0
	fi
	[ "$ty" -ge "$PK_TH" ] || return 0
	r=$(((ty - PK_TH) / PK_RH))
	c=$(((tx - 12) / PK_COLW))
	[ "$c" -lt 0 ] && c=0
	[ "$c" -gt 2 ] && c=2
	line=$(sed -n "$((r * 3 + c + 1))p" "$STATE/pk_page")
	typ=${line%%|*}
	case $typ in S | C) ;; *) return 0 ;; esac
	if [ "$r" -lt "$PK_FAV" ]; then pf=$F_BOLD; else pf=$F_REG; fi
	pn=${line#?|}
	press_cell $((PK_Y + PK_TH + r * PK_RH + 3)) $((PK_X + 14 + c * PK_COLW)) $((PK_COLW - 4)) $((PK_RH - 6)) "$pf" 27 "${pn%%|*}"
	case $typ in
	S)
		IFS='|'
		set -- $line
		unset IFS
		a=$2 b=$3 c=$4
		printf '%s|%s|%s\n' "$a" "$b" "$c" >"$CITY_SEL"
		recent_add "$a" "$b" "$c"
		log "city: $a $b $c"
		touch "$STATE/refetch"
		close_picker chosen
		;;
	C) picker_open 1 "${line#C|}" 0 ;;
	esac
}

# --- Kindle UI control ------------------------------------------------------

ui_off() {
	lipc-set-prop com.lab126.powerd preventScreenSaver 1
	# Hide the system status bar (pillow): it reappears over the dashboard otherwise.
	lipc-set-prop com.lab126.pillow disableEnablePillow disable >/dev/null 2>&1
	stop framework >/dev/null 2>&1
	# Give the framework a moment to release the screen.
	sleep 3
	lipc-set-prop com.lab126.pillow disableEnablePillow disable >/dev/null 2>&1
}

# Rotate the framebuffer: 0 upright, 1 clockwise, 2 upside down, 3 counter-clockwise.
set_rota() {
	echo "$1" >"$STATE/rota"
	rota_node=/sys/class/graphics/fb0/rotate
	if [ -w "$rota_node" ]; then
		echo "$1" >"$rota_node"
	elif command -v fbdepth >/dev/null 2>&1; then
		fbdepth -r "$1" >/dev/null 2>&1
	else
		log "rotation: no way to rotate the framebuffer"
		return 1
	fi
}

ui_on() {
	[ -n "$NATIVE_ROTA" ] && set_rota "$NATIVE_ROTA"
	fbink -q -c -m -M -t regular="$F_MED",px=36 "$T_RETURN" >/dev/null 2>&1
	lipc-set-prop com.lab126.powerd preventScreenSaver 0
	lipc-set-prop com.lab126.pillow disableEnablePillow enable >/dev/null 2>&1
	start framework >/dev/null 2>&1
}

# Touch input device (the Paperwhite 1 has a single one, "cyttsp", which is also what the
# framework reads); falls back to event0.
touch_device() {
	dev=$(awk '
		/^N: Name=/ { name = tolower($0) }
		/^H: Handlers=/ && name ~ /cyttsp|touch|zforce/ {
			if (match($0, /event[0-9]+/)) { print substr($0, RSTART, RLENGTH); exit }
		}' /proc/bus/input/devices 2>/dev/null)
	echo "/dev/input/${dev:-event0}"
}

# Position of the first touch in the 8 raw input events in $1 ("x y", empty if none).
# Events are 16 bytes (32-bit ARM). tr keeps NUL and the record separator out of awk's way;
# the awk turns bytes into numbers.
touch_xy() {
	LC_ALL=C tr '\000\377\005' '\377\376\006' <"$1" | LC_ALL=C awk -v 'RS=\005' '
		function b(p,  r) { r = o[substr($0, p, 1)]; return (r == 255) ? 0 : r }
		BEGIN { for (n = 1; n < 256; n++) o[sprintf("%c", n)] = n }
		{
			for (i = 0; i + 16 <= length($0); i += 16) {
				t = b(i + 9) + 256 * b(i + 10); c = b(i + 11) + 256 * b(i + 12); v = b(i + 13) + 256 * b(i + 14)
				if (t == 3 && c == 53) x = v
				if (t == 3 && c == 54) y = v
				if (t == 1 && c == 330 && v == 1) d = 1
			}
		}
		END { if (d && x != "" && y != "") print x, y }'
}

# Last raw position and whether the finger was lifted, from the raw input events in $1:
# "x y lifted". x and y keep the values $2 and $3 until the events give new ones.
touch_track() {
	if [ ! -f "$1" ]; then
		echo "$2 $3 0"
		return 0
	fi
	LC_ALL=C tr '\000\377\005' '\377\376\006' <"$1" 2>/dev/null | LC_ALL=C awk -v 'RS=\005' -v x="$2" -v y="$3" '
		function b(p,  r) { r = o[substr($0, p, 1)]; return (r == 255) ? 0 : r }
		BEGIN { for (n = 1; n < 256; n++) o[sprintf("%c", n)] = n; up = 0 }
		{
			for (i = 0; i + 16 <= length($0); i += 16) {
				t = b(i + 9) + 256 * b(i + 10); c = b(i + 11) + 256 * b(i + 12); v = b(i + 13) + 256 * b(i + 14)
				if (t == 3 && c == 53) x = v
				if (t == 3 && c == 54) y = v
				if (t == 1 && c == 330 && v == 0) up = 1
			}
		}
		END { print x, y, up }'
}

# Raw panel position -> screen position (sets tx ty): d = quarter turns from the native
# rotation (0 as is, 2 mirrored, 1 and 3 swap axes).
map_xy() {
	case $d in
	0) tx=$1 ty=$2 ;;
	1) tx=$2 ty=$((SCR_H - $1)) ;;
	2) tx=$((SCR_W - $1)) ty=$((SCR_H - $2)) ;;
	*) tx=$((SCR_W - $2)) ty=$1 ;;
	esac
}

# Light swipe on the left edge, like a Kobo: the light follows the finger, up brightens and
# down dims to off. The zone's full height spans the whole range (0-24). The rest of the
# gesture is read in the background while the light is set every ~0.15 s.
# light_swipe RAW_X RAW_Y
light_swipe() {
	sx=$1 sy=$2
	map_xy "$sx" "$sy"
	y0=$ty
	l0=$(light_level_now)
	l0=${l0:-0}
	span=$(px_len $((SW_BOT - SW_TOP)))
	gf=$STATE/swipe.bin
	rm -f "$gf"
	dd if="$tdev" bs=16 count=4000 of="$gf" >/dev/null 2>&1 &
	ddp=$!
	lv=$l0 moved=0 n=0
	while [ "$n" -lt 50 ]; do
		usleep 150000 2>/dev/null || sleep 1
		n=$((n + 1))
		set -- $(touch_track "$gf" "$sx" "$sy")
		[ $# = 3 ] || continue
		sx=$1 sy=$2
		map_xy "$1" "$2"
		dy=$((y0 - ty))
		if [ "$moved" = 0 ] && [ "$dy" -lt 20 ] && [ "$dy" -gt -20 ]; then
			[ "$3" = 1 ] && break
			continue
		fi
		moved=1
		nl=$((l0 + dy * 24 / span))
		[ "$nl" -lt 0 ] && nl=0
		[ "$nl" -gt 24 ] && nl=24
		if [ "$nl" != "$lv" ]; then
			lv=$nl
			if [ "$lv" = 0 ]; then
				lipc-set-prop com.lab126.powerd flIntensity 0
				for n0 in /sys/class/backlight/*/brightness /sys/devices/system/fl_tps6116x/fl_tps6116x0/fl_intensity; do
					[ -w "$n0" ] && echo 0 >"$n0"
				done
			else
				lipc-set-prop com.lab126.powerd flIntensity "$lv"
			fi
			light_live "$lv"
		fi
		[ "$3" = 1 ] && break
	done
	kill "$ddp" 2>/dev/null
	if [ "$moved" = 1 ]; then
		# The light panel then shows the step itself, or the preset it matches.
		rm -f "$STATE/lightidx"
		log "light swipe: $l0 -> $lv"
	fi
}

# Tap (canvas cx cy) on a 64 px button at "X Y" (with a small margin)? A button near an edge
# of the screen reaches that edge: taps at the very bottom (y 752 in landscape) were lost.
on_btn() {
	set -- $1
	ob_l=$(($1 - 8)) ob_r=$(($1 + BTN + 8)) ob_t=$(($2 - 8)) ob_b=$(($2 + BTN + 8))
	[ "$1" -le 48 ] && ob_l=-100
	[ $((CW - $1 - BTN)) -le 48 ] && ob_r=$((CW + 100))
	[ "$2" -le 48 ] && ob_t=-100
	[ $((CH - $2 - BTN)) -le 48 ] && ob_b=$((CH + 100))
	[ "$cx" -ge "$ob_l" ] && [ "$cx" -lt "$ob_r" ] && [ "$cy" -ge "$ob_t" ] && [ "$cy" -lt "$ob_b" ]
}

# Ask the main loop for a full redraw (after a setting changed).
want_redraw() {
	touch "$STATE/redraw"
	kill -USR1 "$main_pid" 2>/dev/null
}

# Row N tapped in the menu (see menu_ids for what is on it).
menu_action() {
	rm -f "$STATE/menu" "$STATE/under.fb"
	ma_id=$(menu_ids | cut -d' ' -f$(($1 + 1)))
	log "menu: $(menu_labels | cut -d'|' -f$(($1 + 1))) ($ma_id)"
	menu_used "$ma_id"
	case $ma_id in
	f)
		# Flip 180 degrees: portrait native/upside down, landscape 0/2.
		if [ "$ORIENT" = landscape ]; then
			if [ "${rota:-0}" = "$LANDSCAPE_ROTA" ]; then nr=$(((LANDSCAPE_ROTA + 2) % 4)); else nr=$LANDSCAPE_ROTA; fi
		elif [ "${rota:-$NATIVE_ROTA}" = "$NATIVE_ROTA" ]; then
			nr=$(((NATIVE_ROTA + 2) % 4))
		else
			nr=$NATIVE_ROTA
		fi
		set_rota "$nr"
		want_redraw
		;;
	v)
		if [ "$(cat "$LAYOUT_FILE" 2>/dev/null)" = weather ]; then nl=simple; else nl=weather; fi
		echo "$nl" >"$STATE/layoutreq"
		echo "$nl" >"$LAYOUT_FILE"
		want_redraw
		;;
	o)
		if [ "$ORIENT" = landscape ]; then
			echo portrait >"$STATE/orient"
			set_rota "$NATIVE_ROTA"
		else
			echo landscape >"$STATE/orient"
			set_rota "$LANDSCAPE_ROTA"
		fi
		want_redraw
		;;
	r)
		# Weather refresh: the main loop shows "se actualizează…", fetches and redraws.
		touch "$STATE/fetchnow"
		kill -USR1 "$main_pid" 2>/dev/null
		;;
	t)
		if [ "$UNIT_T" = F ]; then echo C >"$DIR/temp.sel"; else echo F >"$DIR/temp.sel"; fi
		want_redraw
		;;
	c)
		if [ "$CLK12" = 1 ]; then echo 24 >"$DIR/clock.sel"; else echo 12 >"$DIR/clock.sel"; fi
		want_redraw
		;;
	*)
		if [ "$UI_LANG" = en ]; then echo ro >"$LANG_SEL"; else echo en >"$LANG_SEL"; fi
		want_redraw
		;;
	esac
}

# Touch: the panel does not follow the screen rotation, so raw coordinates are mapped to the
# current screen (d = quarter turns from the native rotation: 0 as is, 2 mirrored, 1 and 3 swap
# axes), then to canvas units. Each loop opens the device afresh, so the rest of a tap's events
# are dropped while sleeping.
touch_watch() {
	tdev=$(touch_device)
	tf=$STATE/touch.bin
	while :; do
		dd if="$tdev" bs=16 count=8 of="$tf" >/dev/null 2>&1
		xy=$(touch_xy "$tf")
		if [ -n "$xy" ]; then
			set -- $xy
			rx=$1 ry=$2
			ORIENT=$(cat "$STATE/orient" 2>/dev/null)
			LAYOUT=$(cat "$LAYOUT_FILE" 2>/dev/null)
			rota=$(cat "$STATE/rota" 2>/dev/null)
			layout_init
			load_lang
			d=$(((${rota:-$NATIVE_ROTA} - NATIVE_ROTA + 4) % 4))
			map_xy "$rx" "$ry"
			cx=$(((tx - OX) * 1000 / S))
			cy=$(((ty - OY) * 1000 / S))
			popup=$(cut -d' ' -f1 "$STATE/menu" 2>/dev/null)
			log "tap $rx,$ry -> $cx,$cy ($ORIENT, rotation ${rota:-?}${popup:+, $popup open})"
			if [ -f "$STATE/picker" ]; then
				picker_tap "$cx" "$cy"
			elif [ "$popup" = main ]; then
				if [ "$cx" -ge "$MENU_X" ] && [ "$cx" -lt $((MENU_X + MENU_W)) ] && [ "$cy" -ge "$MENU_Y" ] && [ "$cy" -lt $((MENU_Y + MENU_H)) ]; then
					mr=$(((cy - MENU_Y) / 54))
					press_row "$mr"
					menu_action "$mr"
				else
					tap_outside "$B_MENU"
				fi
			elif [ "$popup" = light ]; then
				if [ "$cx" -lt "${SWIPE_W:-60}" ] && [ "$cy" -ge "$SW_TOP" ] && [ "$cy" -lt "$SW_BOT" ]; then
					# Swipe on the bar: the arrow follows; the pop-up stays LIGHT_SECONDS more.
					# A new token first, so the running timer cannot close it mid-swipe
					# (2.06 closed it during a long swipe).
					echo "light swipe$$" >"$STATE/menu"
					light_swipe "$rx" "$ry"
					if [ -f "$STATE/menu" ]; then
						echo "light $(date +%s)$$" >"$STATE/menu"
						popup_timer "${LIGHT_SECONDS:-10}"
					fi
				elif [ "$cx" -ge "$LP_X" ] && [ "$cx" -lt $((LP_X + LP_W)) ] && [ "$cy" -ge "$LP_Y" ] && [ "$cy" -lt $((LP_Y + LP_H)) ]; then
					: # on the bubble: nothing to do there
				else
					tap_outside "$B_LIGHT"
				fi
			elif on_btn "$B_MENU"; then
				fb_save
				press_btn menu "$B_MENU"
				open_popup main "${MENU_SECONDS:-15}"
			elif on_btn "$B_LIGHT"; then
				fb_save
				press_btn light "$B_LIGHT"
				open_popup light "${LIGHT_SECONDS:-10}"
			elif on_btn "$B_EXIT"; then
				press_btn exit "$B_EXIT"
				kill -TERM "$main_pid" 2>/dev/null
				return 0
			elif on_btn "$B_CITY"; then
				fb_save
				press_btn city "$B_CITY"
				picker_open 0 "" 0
			elif [ "${LIGHT_SWIPE:-1}" = 1 ] && [ "$cx" -lt "${SWIPE_W:-60}" ] &&
				[ "$cy" -ge "$SW_TOP" ] && [ "$cy" -lt "$SW_BOT" ]; then
				light_swipe "$rx" "$ry"
			fi
		fi
		# A short pause drops the rest of this tap's events; taps during it are lost, so it
		# is kept short (2.055 waited 1 s).
		usleep 300000 2>/dev/null || sleep 1
	done
}

# Automatic frontlight (AUTO_LIGHT=1). Applied only when the period changes, so a manual pick
# from the light panel stays until the next change. Night (NIGHT_START to NIGHT_END): off.
# From sunset to night: EVENING_LIGHT (Mediu), or off while the battery is under BATT_LOW %
# and not charging. Daytime and before sunrise: left as it is.
auto_light() {
	[ "${AUTO_LIGHT:-1}" = 1 ] || return 0
	if is_night; then
		al=night
	elif after_sunset; then
		al=evening
		[ -n "$ST_LVL" ] && [ "$ST_CHG" != 1 ] && [ "$ST_LVL" -lt "${BATT_LOW:-25}" ] && al=evening-low
	else
		al=day
	fi
	[ "$al" = "$LAST_AUTO" ] && return 0
	LAST_AUTO=$al
	log "auto light: $al"
	case $al in
	night | evening-low) light_set 0 ;;
	evening) light_set "${EVENING_LIGHT:-3}" ;;
	esac
}

# After today's sunset (W_SUNSET from the forecast; without it, the "night" flag after noon).
after_sunset() {
	nm=$(date +%H%M | sed 's/^0*//')
	if [ -n "$W_SUNSET" ]; then
		ss=$(echo "$W_SUNSET" | tr -d ':' | sed 's/^0*//')
		[ "${nm:-0}" -ge "${ss:-0}" ]
	else
		[ "$W_IS_DAY" = 0 ] && [ "${nm:-0}" -ge 1200 ]
	fi
}

# --- Main loop -------------------------------------------------------------

run() {
	mkdir -p "$STATE"
	if is_running; then
		echo "already running (pid $(cat "$PIDFILE"))"
		return 1
	fi
	echo $$ >"$PIDFILE"
	echo "$LAYOUT" >"$LAYOUT_FILE"
	trim_log
	log "start v$VERSION ($LAYOUT layout, $ORIENT)"

	WATCH_PID=""
	EVENT_PID=""
	SLEEP_PID=""
	trap 'shutdown' TERM INT HUP
	# Power events (charger plugged/unplugged, battery level) redraw the status bar now
	# rather than at the next minute tick.
	trap ':' USR1

	NATIVE_ROTA=$(cat /sys/class/graphics/fb0/rotate 2>/dev/null)
	rm -f "$STATE/redraw" "$STATE/softdraw" "$STATE/fetchnow" "$STATE/layoutreq" "$STATE/lightidx" "$STATE/picker" "$STATE/refetch" "$STATE/menu" "$STATE/fetching" "$STATE/drawing" "$STATE/under.fb" "$STATE/clockdraw" "$STATE/menuorder"
	load_city
	recent_init
	echo "$NATIVE_ROTA" >"$STATE/rota"
	ui_off
	if [ "$ORIENT" = landscape ]; then
		set_rota "$LANDSCAPE_ROTA"
		sleep 2
	fi
	layout_init
	if [ "$ORIENT" = landscape ] && [ "$SCR_W" -lt "$SCR_H" ]; then
		log "landscape: screen is still ${SCR_W}x${SCR_H} after rotating; using portrait"
		set_rota "$NATIVE_ROTA"
		ORIENT=portrait
		layout_init
	fi
	echo "$ORIENT" >"$STATE/orient"
	log "screen ${SCR_W}x${SCR_H}, scale $S/1000, rotate $(cat /sys/class/graphics/fb0/rotate 2>&1)"
	log "curl: $(curl -V 2>&1 | head -n 1)"
	log "light: powerd $(light_level_now) nodes: $(ls -d /sys/class/backlight/* /sys/devices/system/fl_* 2>&1 | tr '\n' ' ')"
	log "services: $(initctl list 2>/dev/null | grep -i -e pillow -e gui -e framework | tr '\n' ';')"

	# Touch buttons, menu, light panel and swipe: see touch_watch.
	main_pid=$$
	touch_watch &
	WATCH_PID=$!

	# powerd broadcasts charging, notCharging, USBPlugin, USBUnplug and battLevelChanged;
	# on any of them, poke the main loop to re-read the status.
	(
		lipc-wait-event -m com.lab126.powerd '*' 2>/dev/null |
			while read -r _; do kill -USR1 "$main_pid" 2>/dev/null || break; done
	) &
	EVENT_PID=$!

	last_fetch=0
	last_warn=0
	last_pollen=0
	last_ntp=0
	fail_n=0
	retry_at=""
	LAST_AUTO=""
	first=1
	last_day=""
	while :; do
		set -- $(date '+%s %M %j')
		now=$1 min=${2#0} today=$3

		# Full redraw (with flash) at start and every FULL_REFRESH_MINUTES; full redraw
		# for the new date after midnight; otherwise only the clock and changed status bar.
		# An open pop-up is not drawn over: only the clock (the city picker: nothing), and the
		# date change waits until it closes.
		if [ -f "$STATE/picker" ]; then
			today=$last_day
		elif [ -f "$STATE/menu" ]; then
			draw_partial
			today=$last_day
		elif [ "$first" = 1 ] || [ $((min % FULL_REFRESH_MINUTES)) -eq 0 ]; then
			draw 1
		elif [ "$today" != "$last_day" ]; then
			draw 0
		else
			draw_partial
		fi
		last_day=$today
		first=0

		if [ $((now - last_fetch)) -ge $(($(weather_minutes) * 60 - 30)) ]; then
			if ! fetch_weather; then
				# Often the Wi-Fi is not up yet right after start: try again in 15 s
				# (up to 3 times in a row), not only at the next minute.
				if [ "${fail_n:-0}" -lt 3 ]; then
					fail_n=$((${fail_n:-0} + 1))
					retry_at=$((now + 15))
				fi
			else
				fail_n=0 retry_at=""
				last_fetch=$now
				if [ $((now - last_warn)) -ge $((${WARN_MINUTES:-30} * 60 - 30)) ]; then
					fetch_warnings && last_warn=$now
				fi
				if [ $((now - last_pollen)) -ge $((${POLLEN_MINUTES:-60} * 60 - 30)) ]; then
					fetch_pollen && last_pollen=$now
				fi
				[ -f "$STATE/picker" ] || [ -f "$STATE/menu" ] || draw 0
			fi
		fi

		[ -f "$STATE/picker" ] || auto_light

		if [ $((now - last_ntp)) -ge 3600 ]; then
			if ntpdate "$NTP_SERVER" >/dev/null 2>&1; then
				last_ntp=$now
			else
				log "ntp: sync with $NTP_SERVER failed"
				last_ntp=$((now - 3000)) # retry in ~10 minutes
			fi
		fi

		sec=$(date +%S)
		sec=${sec#0}
		tick_end=$(($(date +%s) + 60 - ${sec:-0}))
		# One-second steps until the next minute: a tap sets the redraw flag and signals
		# USR1 (which cuts the step short), and the flag is also polled, so a signal that
		# arrives while the loop is busy drawing is not lost.
		while [ "$(date +%s)" -lt "$tick_end" ]; do
			sleep 1 &
			SLEEP_PID=$!
			wait "$SLEEP_PID"
			wrc=$?
			if [ -f "$STATE/redraw" ]; then
				rm -f "$STATE/redraw"
				if [ -f "$STATE/layoutreq" ]; then
					LAYOUT=$(cat "$STATE/layoutreq")
					rm -f "$STATE/layoutreq"
					echo "$LAYOUT" >"$LAYOUT_FILE"
				fi
				ORIENT=$(cat "$STATE/orient" 2>/dev/null)
				load_lang
				if [ -f "$STATE/refetch" ]; then
					# New city: drop the old forecast and fetch the new one.
					rm -f "$STATE/refetch" "$WEATHER_ENV" "$WARN_ENV" "$POLLEN_ENV"
					load_city
					fbink -q -c -m -M -t regular="$F_MED",px=36 "$T_LOADING" >/dev/null 2>&1
					if fetch_weather; then last_fetch=$(date +%s); else last_fetch=0; fi
					fetch_warnings && last_warn=$(date +%s)
					fetch_pollen && last_pollen=$(date +%s)
				fi
				sleep 1
				layout_init
				draw 1
			elif [ -f "$STATE/fetchnow" ]; then
				rm -f "$STATE/fetchnow"
				log "weather: manual refresh"
				# Close the menu and say "se actualizează…" where the update time goes.
				touch "$STATE/fetching"
				[ -f "$STATE/picker" ] || draw 1
				if fetch_weather; then last_fetch=$(date +%s); fi
				fetch_warnings && last_warn=$(date +%s)
				fetch_pollen && last_pollen=$(date +%s)
				rm -f "$STATE/fetching"
				[ -f "$STATE/picker" ] || draw 0
			elif [ -n "$retry_at" ] && [ "$(date +%s)" -ge "$retry_at" ]; then
				retry_at=""
				log "weather: retry $fail_n"
				if fetch_weather; then
					fail_n=0
					last_fetch=$(date +%s)
					fetch_warnings && last_warn=$(date +%s)
					fetch_pollen && last_pollen=$(date +%s)
					[ -f "$STATE/picker" ] || [ -f "$STATE/menu" ] || draw 1
				elif [ "$fail_n" -lt 3 ]; then
					fail_n=$((fail_n + 1))
					retry_at=$(($(date +%s) + 15))
				fi
			elif [ -f "$STATE/clockdraw" ]; then
				# A pop-up closed and the screen under it came back: the clock may be old.
				rm -f "$STATE/clockdraw"
				[ -f "$STATE/picker" ] || [ -f "$STATE/menu" ] || draw_partial
			elif [ -f "$STATE/softdraw" ]; then
				rm -f "$STATE/softdraw"
				[ -f "$STATE/picker" ] || draw 0
			elif [ "$wrc" -gt 128 ] && [ ! -f "$STATE/picker" ]; then
				refresh_status
			fi
		done
	done
}

shutdown() {
	trap '' TERM INT HUP
	log "stop"
	# Children: the minute sleep, the power-button watcher (plus its dd) and the powerd
	# event watcher (plus its lipc-wait-event). When started via setsid we lead our own
	# process group: signal all of it (TERM is ignored here now, so this process survives).
	if [ "$(cut -d' ' -f5 /proc/$$/stat)" = "$$" ]; then
		kill -TERM -$$ 2>/dev/null
	else
		[ -n "$WATCH_PID" ] && pkill -P "$WATCH_PID" 2>/dev/null
		[ -n "$EVENT_PID" ] && pkill -P "$EVENT_PID" 2>/dev/null
		pkill -P $$ 2>/dev/null
	fi
	rm -f "$PIDFILE"
	ui_on
	exit 0
}

# Orientation argument: portrait (default) or landscape.
orient_arg() {
	case "${1:-portrait}" in
	landscape) echo landscape ;;
	*) echo portrait ;;
	esac
}

# Layout argument for start/run: simple (default) or weather (5 days). The names of the old
# layouts without buttons (simplistic, forecast) map to these.
layout_arg() {
	case "${1:-simple}" in
	simple | simplistic) echo simple ;;
	weather | forecast) echo weather ;;
	*)
		echo "unknown layout '$1' (use simple or weather)" >&2
		exit 2
		;;
	esac
}

# Up to v2.051 this was extensions/rekindle (with bin/rekindle.sh). On the first start of the
# renamed app: stop the old one if it still runs, and take over its choices (city, °C/°F,
# 12/24h, language). The old folder can then be deleted.
OLD_DIR=/mnt/us/extensions/rekindle
migrate_old() {
	[ -d "$OLD_DIR" ] || return 0
	if [ -f /tmp/rekindle/pid ] && kill -0 "$(cat /tmp/rekindle/pid)" 2>/dev/null; then
		"$OLD_DIR/bin/rekindle.sh" stop >/dev/null 2>&1
		sleep 3
	fi
	for f in city.sel temp.sel clock.sel lang.sel; do
		if [ -f "$OLD_DIR/$f" ] && [ ! -f "$DIR/$f" ]; then
			cp "$OLD_DIR/$f" "$DIR/$f" && log "migrate: $f from $OLD_DIR"
		fi
	done
}

case "$1" in
start)
	layout=$(layout_arg "$2") || exit 2
	if is_running; then
		echo "meteoalarmkindle already running"
		exit 0
	fi
	mkdir -p "$STATE"
	migrate_old
	# Keep the log short: only the last 300 lines survive a restart.
	if [ -f "$LOG" ] && [ "$(wc -l <"$LOG")" -gt 300 ]; then
		tail -n 300 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
	fi
	setsid "$0" run "$layout" "$(orient_arg "$3")" >>"$LOG" 2>&1 </dev/null &
	;;
stop)
	if is_running; then
		kill -TERM "$(cat "$PIDFILE")"
	else
		echo "meteoalarmkindle not running"
	fi
	;;
status)
	if is_running; then
		echo "running (pid $(cat "$PIDFILE"), $(cat "$LAYOUT_FILE" 2>/dev/null) layout)"
	else
		echo "stopped"
	fi
	[ -f "$WEATHER_ENV" ] && cat "$WEATHER_ENV"
	;;
run)
	LAYOUT=$(layout_arg "$2") || exit 2
	ORIENT=$(orient_arg "$3")
	run
	;;
fetch)
	fetch_weather && cat "$WEATHER_ENV"
	;;
preview)
	# Draw one screen from the saved data and exit (for testing): preview LAYOUT ORIENT [menu|light|pick|pick2|pick:COUNTY]
	LAYOUT=$(layout_arg "$2") || exit 2
	ORIENT=$(orient_arg "$3")
	mkdir -p "$STATE"
	load_city
	recent_init
	layout_init
	draw 1
	case $4 in
	menu) draw_menu ;;
	light) draw_light_popup ;;
	pick | pick:* | pick2)
		# pick = counties (pick2: second tab), pick:COUNTY = that county's towns.
		case $4 in
		pick) pk_l=0 pk_c="" pk_p=0 ;;
		pick2) pk_l=0 pk_c="" pk_p=1 ;;
		*) pk_l=1 pk_c=${4#pick:} pk_p=0 ;;
		esac
		echo "$pk_l|$pk_c|$pk_p|0" >"$STATE/picker"
		pk_build "$pk_l" "$pk_c"
		draw_picker
		fbink -q -s >/dev/null 2>&1
		rm -f "$STATE/picker"
		;;
	esac
	;;
*)
	echo "usage: $0 start [simple|weather] [portrait|landscape]|stop|status|run [...]|fetch|preview [...]" >&2
	exit 2
	;;
esac