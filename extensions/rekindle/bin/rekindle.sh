#!/bin/sh
# rekindle: always-on time & weather dashboard for a jailbroken Kindle.
# Target: Kindle 7th gen (KT2), FW 5.8.x, BusyBox 1.17 ash, FBInk in /usr/bin.
#
# Usage: rekindle.sh start [simplistic|forecast] | stop | status | run [simplistic|forecast] | fetch
#   start   launch the dashboard in the background (used by KUAL); the layout is the
#           current weather with an hourly rain chart when rain is due (simplistic,
#           default) or with a 5-day forecast (forecast)
#   stop    stop it and bring the normal Kindle UI back
#   status  print whether it is running (and its layout) and the last weather data
#   run     run the dashboard loop in the foreground
#   fetch   fetch weather once and print the parsed values
#
# While running, pressing the power button exits back to the Kindle UI.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin:/mnt/us/libkh/bin

DIR=$(cd "$(dirname "$0")/.." && pwd)
. "$DIR/rekindle.conf"
LANDSCAPE_ROTA=${LANDSCAPE_ROTA:-2}
LIGHT_1=${LIGHT_1:-4}
LIGHT_2=${LIGHT_2:-10}
LIGHT_3=${LIGHT_3:-24}
export TZ="$TZ_POSIX"

STATE=/tmp/rekindle
PIDFILE=$STATE/pid
WEATHER_ENV=$STATE/weather.env
LAYOUT_FILE=$STATE/layout
LOG=$DIR/rekindle.log

FONTS=/usr/java/lib/fonts
F_BOLD=$FONTS/Amazon-Ember-Bold.ttf
F_REG=$FONTS/Amazon-Ember-Regular.ttf
F_MED=$FONTS/Amazon-Ember-Medium.ttf
# Firmware 5.6 has no Amazon Ember: fall back to the Liberation Sans files shipped in fonts/.
if [ ! -f "$F_REG" ]; then
	F_BOLD=$DIR/fonts/LiberationSans-Bold.ttf
	F_REG=$DIR/fonts/LiberationSans-Regular.ttf
	F_MED=$DIR/fonts/LiberationSans-Bold.ttf
fi

log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"
}

trim_log() {
	[ -f "$LOG" ] || return 0
	if [ "$(wc -c <"$LOG")" -gt 200000 ]; then
		tail -n 500 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
	fi
}

# UI language (ro or en), kept in lang.sel. set_strings loads the texts of the language.
LANG_SEL=$DIR/lang.sel
load_lang() {
	l=${REKINDLE_LANG:-$(cat "$LANG_SEL" 2>/dev/null)}
	if [ "$l" = en ]; then
		UI_LANG=en
		T_UNTIL=until T_NOW=now T_RAIN=Rain T_RAINFROM="Rain from" T_MAX=max
		T_UPDATED=updated T_NODATA="no data since" T_LOADING="Loading weather…"
		T_RETURN="Returning to Kindle…" T_RAINW=Raining T_SNOWW=Snowing
		T_LIGHT="Off Min Medium Max" T_PICK="Choose city" T_PICKTOWN="choose town"
		T_BACK=Back T_PAGE=Page T_CLOSE=Close T_LANGBTN=RO
	else
		UI_LANG=ro
		T_UNTIL="până la" T_NOW=acum T_RAIN=Ploaie T_RAINFROM="Ploaie de la" T_MAX=maxim
		T_UPDATED=actualizat T_NODATA="fără date din" T_LOADING="Se descarcă vremea…"
		T_RETURN="Revenire la Kindle…" T_RAINW=Plouă T_SNOWW=Ninge
		T_LIGHT="Oprit Minim Mediu Maxim" T_PICK="Alege orașul" T_PICKTOWN="alege localitatea"
		T_BACK=Înapoi T_PAGE=Pagina T_CLOSE=Închide T_LANGBTN=EN
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
fetch_weather() {
	mkdir -p "$STATE"
	tz_enc=$(echo "$TZ_IANA" | sed 's#/#%2F#g')
	url="http://api.open-meteo.com/v1/forecast?latitude=$LATITUDE&longitude=$LONGITUDE"
	url="$url&current=temperature_2m,weather_code,precipitation,is_day"
	url="$url&hourly=precipitation_probability,precipitation"
	url="$url&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max"
	url="$url&forecast_days=6&forecast_hours=$RAIN_LOOKAHEAD_HOURS&timezone=$tz_enc"

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
	if [ -z "$temp" ] || [ -z "$code" ]; then
		log "weather: unexpected response: $(cut -c1-300 "$json" 2>/dev/null)"
		return 1
	fi

	tmax=$(json_arr "$daily" temperature_2m_max | cut -d, -f1)
	tmin=$(json_arr "$daily" temperature_2m_min | cut -d, -f1)

	# The next five days (today, the first entry, is skipped) for the forecast layout:
	# weekday names (computed here; BusyBox date cannot parse dates), weather codes,
	# rounded high/low and the day's highest precipitation probability.
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
			ds = ""; cs = ""; his = ""; los = ""; ps = ""
			for (i = 2; i <= n; i++) {
				if (hi[i] == "null" || lo[i] == "null") continue
				gsub(/"/, "", t[i])
				y = substr(t[i], 1, 4) + 0; m = substr(t[i], 6, 2) + 0; d = substr(t[i], 9, 2) + 0
				if (m < 3) y--
				w = (y + int(y / 4) - int(y / 100) + int(y / 400) + off[m] + d) % 7
				# BusyBox awk reads `sep (...)` as a call to a function sep: no
				# parenthesised term directly after a variable in a concatenation.
				sep = (ds == "") ? "" : " "
				cv = (c[i] == "null") ? "-1" : c[i]
				pv = (p[i] == "null") ? 0 : sprintf("%d", p[i])
				hv = r(hi[i]); lv = r(lo[i])
				ds = ds sep name[w + 1]
				cs = cs sep cv; his = his sep hv; los = los sep lv; ps = ps sep pv
			}
			printf "W_D_DAYS=\"%s\"\nW_D_CODES=\"%s\"\nW_D_MAX=\"%s\"\nW_D_MIN=\"%s\"\nW_D_POP=\"%s\"\n", ds, cs, his, los, ps
		}')

	# Per-hour series for the rain chart (hour, probability, rainy flag), the first rainy
	# hour, the hour that rainy run ends (empty if it outlasts the window), and the max probability.
	rain=$(awk -v times="$(json_arr "$hourly" time)" \
		-v probs="$(json_arr "$hourly" precipitation_probability)" \
		-v amts="$(json_arr "$hourly" precipitation)" \
		-v thr="$RAIN_PROBABILITY" '
		BEGIN {
			n = split(times, t, ","); split(probs, p, ","); split(amts, a, ",")
			hours = ""; ps = ""; wets = ""; at = ""; stop = ""; maxp = 0
			for (i = 1; i <= n; i++) {
				gsub(/"/, "", t[i]); hr = substr(t[i], 12, 5)
				pv = (p[i] == "null") ? 0 : p[i] + 0
				av = (a[i] == "null") ? 0 : a[i] + 0
				wet = (pv >= thr || av >= 0.1) ? 1 : 0
				if (pv > maxp) maxp = pv
				if (at == "" && wet) at = hr
				else if (at != "" && stop == "" && !wet) stop = hr
				sep = (i > 1) ? " " : ""
				hours = hours sep hr
				ps = ps sep sprintf("%d", pv)
				wets = wets sep wet
			}
			printf "W_HOURS=\"%s\"\nW_PROBS=\"%s\"\nW_WET=\"%s\"\n", hours, ps, wets
			printf "W_RAIN_AT=\"%s\"\nW_RAIN_END=\"%s\"\nW_RAIN_MAXP=%d\n", at, stop, maxp
		}')

	{
		echo "W_TEMP=$temp"
		echo "W_CODE=$code"
		echo "W_PRECIP=${precip:-0}"
		echo "W_IS_DAY=${is_day:-1}"
		echo "W_TMAX=$tmax"
		echo "W_TMIN=$tmin"
		echo "$rain"
		echo "$days"
		echo "W_FETCHED=$(date +%s)"
	} >"$WEATHER_ENV.tmp" && mv "$WEATHER_ENV.tmp" "$WEATHER_ENV"
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

# --- Drawing ---------------------------------------------------------------

# The layout is authored on a 600x800 canvas (Kindle Basic/Touch). layout_init scales it
# uniformly to the real screen and centers it, so the same numbers work on 758x1024 and
# 1072x1448 Paperwhites. Every helper below takes canvas coordinates.
# REKINDLE_VIEW=WxH overrides the target size (testing other sizes on one device).
layout_init() {
	# Canvas: 600x800 portrait; 800x600 in landscape (ORIENT).
	CW=600 CH=800
	[ "$ORIENT" = landscape ] && CW=800 CH=600
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
# fb_text FONT PX TOP LEFT RIGHT TEXT [extra fbink flags...]: centered in the [LEFT, 600-RIGHT] band.
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

fb_rect() {
	# fb_rect TOP LEFT WIDTH HEIGHT COLOR
	fbink -q -b -B "$5" -k top="$(px_y "$1")",left="$(px_x "$2")",width="$(px_len "$3")",height="$(px_len "$4")" >/dev/null 2>&1
}

# fb_refresh TOP LEFT WIDTH HEIGHT: refresh only this rectangle of the screen (non-flashing).
fb_refresh() {
	fbink -q -s top="$(px_y "$1")",left="$(px_x "$2")",width="$(px_len "$3")",height="$(px_len "$4")" >/dev/null 2>&1
}

# fb_image FILE X Y W H: draw an icon scaled to W x H canvas px.
fb_image() {
	fbink -q -b -g file="$1",x="$(px_x "$2")",y="$(px_y "$3")",w="$(px_len "$4")",h="$(px_len "$5")" >/dev/null 2>&1
}

# Width in device px of TEXT at device PX in FONT, measured without drawing (fgless + bgless).
text_width() {
	fbink -q -b -O -T -E -t regular="$1",px="$2",top=0,left=0 -- "$3" 2>/dev/null |
		sed -n 's/.*lastRect_Width=\([0-9]*\).*/\1/p'
}

# Hourly rain chart on the content margins (x 40..560): one bar per forecast hour,
# height = precipitation probability, black when the hour counts as rainy, light gray
# otherwise; a dotted line marks RAIN_PROBABILITY and every third hour is labelled below.
# draw_rain_chart TOP HEIGHT
draw_rain_chart() {
	ct=$1 ch=$2
	set -- $W_PROBS
	n=$#
	[ "$n" -gt 0 ] || return 0
	pitch=$((CHART_W / n))
	bw=$((pitch - 8))
	ty=$((ct + ch - RAIN_PROBABILITY * ch / 100))
	x=$CHART_L
	while [ "$x" -lt $((CHART_L + CHART_W)) ]; do
		fb_rect "$ty" "$x" 4 2 GRAY5
		x=$((x + 10))
	done
	hrs="$W_HOURS " wets="$W_WET "
	i=0
	for p in $W_PROBS; do
		hr=${hrs%% *} hrs=${hrs#* }
		wet=${wets%% *} wets=${wets#* }
		bh=$((p * ch / 100))
		[ "$bh" -lt 3 ] && bh=3
		color=GRAYA
		[ "$wet" = 1 ] && color=BLACK
		x=$((CHART_L + i * pitch + 4))
		fb_rect $((ct + ch - bh)) "$x" "$bw" "$bh" "$color"
		[ $((i % 3)) -eq 0 ] && fb_ltext "$F_REG" 20 $((ct + ch + 8)) $((x - 2)) "$hr" -C GRAY5
		i=$((i + 1))
	done
}

# Compact current-weather row (y 344..472) shared by the rain and forecast layouts.
# Uses ICON, DESC, temp and hilo from draw.
draw_now_row() {
	fb_image "$DIR/icons/$ICON.png" 36 352 120 120
	fb_ltext "$F_BOLD" 112 344 170 "$temp"
	fb_rtext "$F_REG" 32 366 560 "$DESC"
	[ -n "$hilo" ] && fb_rtext "$F_REG" 30 412 560 "$hilo" -C GRAY5
}

# Rain banner: light gray band (56 tall) with the rain window in bold and the peak
# chance in gray. Text is drawn background-less (-O) so the band shows through.
# draw_rain_banner TOP
draw_rain_banner() {
	fb_rect "$1" 40 520 56 GRAYD
	fb_ltext "$F_BOLD" 34 $(($1 + 10)) 60 "$rain_text" -O
	fb_rtext "$F_REG" 28 $(($1 + 14)) 540 "$T_MAX $W_RAIN_MAXP%" -O -C GRAY5
}

# Landscape rain banner: gray box (84 tall) with the rain window in bold and the peak
# chance under it. draw_rain_banner_box TOP... as LEFT TOP WIDTH
draw_rain_banner_box() {
	fb_rect "$2" "$1" "$3" 84 GRAYD
	fb_ltext "$F_BOLD" 30 $(($2 + 8)) $(($1 + 16)) "$rain_text" -O
	fb_ltext "$F_REG" 26 $(($2 + 48)) $(($1 + 16)) "$T_MAX $W_RAIN_MAXP%" -O -C GRAY5
}

# Day rain chip: the banner's gray band at day scale, around a bold percentage.
# draw_chip LEFT TOP TEXT
draw_chip() {
	w=$(text_width "$F_BOLD" "$(px_len 20)" "$3")
	fb_rect "$2" "$1" $((${w:-0} * 1000 / S + 14)) 26 GRAYD
	fb_ltext "$F_BOLD" 20 $(($2 + 3)) $(($1 + 7)) "$3" -O
}

# Forecast rows on the content margins: weekday, icon, rain chip (only when the day's
# chance reaches RAIN_PROBABILITY), low, a low-to-high bar on a scale shared by the
# rows shown (gray track, black range), high. Overwrites ICON/DESC via describe.
# draw_forecast TOP ROW_HEIGHT ROWS
draw_forecast() {
	ft=$1 fh=$2 fn=$3
	set -- $W_D_MAX
	[ $# -gt 0 ] || return 0
	[ "$fn" -gt $# ] && fn=$#
	# Scale over the rows actually drawn.
	lo_all=$(echo "$W_D_MIN" | awk -v n="$fn" '{ m = $1; for (i = 2; i <= n; i++) if ($i < m) m = $i; print m }')
	hi_all=$(echo "$W_D_MAX" | awk -v n="$fn" '{ m = $1; for (i = 2; i <= n; i++) if ($i > m) m = $i; print m }')
	span=$((hi_all - lo_all))
	[ "$span" -lt 1 ] && span=1
	bl=272 br=496
	days="$W_D_DAYS " codes="$W_D_CODES " maxs="$W_D_MAX " mins="$W_D_MIN " pops="$W_D_POP "
	i=0
	while [ "$i" -lt "$fn" ]; do
		wday=$(wd_name "${days%% *}") days=${days#* }
		code=${codes%% *} codes=${codes#* }
		hi=${maxs%% *} maxs=${maxs#* }
		lo=${mins%% *} mins=${mins#* }
		pop=${pops%% *} pops=${pops#* }
		mid=$((ft + i * fh + fh / 2))

		describe "$code" 1
		fb_ltext "$F_BOLD" 26 $((mid - 17)) 40 "$wday"
		fb_image "$DIR/icons/$ICON.png" 100 $((mid - 19)) 38 38
		[ "$pop" -ge "$RAIN_PROBABILITY" ] && draw_chip 148 $((mid - 13)) "$pop%"
		fb_rtext "$F_REG" 26 $((mid - 17)) 258 "$(tconv "$lo")°" -C GRAY5
		fb_rect $((mid - 2)) $bl $((br - bl)) 4 GRAYA
		x1=$((bl + (lo - lo_all) * (br - bl) / span))
		x2=$((bl + (hi - lo_all) * (br - bl) / span))
		[ $((x2 - x1)) -lt 6 ] && x2=$((x1 + 6))
		fb_rect $((mid - 5)) $x1 $((x2 - x1)) 10 BLACK
		fb_rtext "$F_BOLD" 26 $((mid - 17)) 560 "$(tconv "$hi")°"
		i=$((i + 1))
	done
}

# Landscape forecast column (x 430..770): weekday, icon, rain chip, low, a low-to-high bar
# on a scale shared by the rows shown, high.
# draw_forecast_col TOP ROW_HEIGHT ROWS
draw_forecast_col() {
	ft=$1 fh=$2 fn=$3
	set -- $W_D_MAX
	[ $# -gt 0 ] || return 0
	[ "$fn" -gt $# ] && fn=$#
	lo_all=$(echo "$W_D_MIN" | awk -v n="$fn" '{ m = $1; for (i = 2; i <= n; i++) if ($i < m) m = $i; print m }')
	hi_all=$(echo "$W_D_MAX" | awk -v n="$fn" '{ m = $1; for (i = 2; i <= n; i++) if ($i > m) m = $i; print m }')
	span=$((hi_all - lo_all))
	[ "$span" -lt 1 ] && span=1
	bl=604 br=708
	days="$W_D_DAYS " codes="$W_D_CODES " maxs="$W_D_MAX " mins="$W_D_MIN " pops="$W_D_POP "
	i=0
	while [ "$i" -lt "$fn" ]; do
		wday=$(wd_name "${days%% *}") days=${days#* }
		code=${codes%% *} codes=${codes#* }
		hi=${maxs%% *} maxs=${maxs#* }
		lo=${mins%% *} mins=${mins#* }
		pop=${pops%% *} pops=${pops#* }
		mid=$((ft + i * fh + fh / 2))

		describe "$code" 1
		fb_ltext "$F_BOLD" 30 $((mid - 20)) 430 "$wday"
		fb_image "$DIR/icons/$ICON.png" 492 $((mid - 22)) 44 44
		[ "$pop" -ge "$RAIN_PROBABILITY" ] && draw_chip 494 $((mid + 24)) "$pop%"
		fb_rtext "$F_REG" 28 $((mid - 19)) 596 "$(tconv "$lo")°" -C GRAY5
		fb_rect $((mid - 2)) $bl $((br - bl)) 4 GRAYA
		x1=$((bl + (lo - lo_all) * (br - bl) / span))
		x2=$((bl + (hi - lo_all) * (br - bl) / span))
		[ $((x2 - x1)) -lt 6 ] && x2=$((x1 + 6))
		fb_rect $((mid - 5)) $x1 $((x2 - x1)) 10 BLACK
		fb_rtext "$F_BOLD" 28 $((mid - 19)) 770 "$(tconv "$hi")°"
		i=$((i + 1))
	done
}

# Touch buttons at the top left (BTN square, BTN_P apart from BX at BY): light, flip, view,
# orientation, exit.
draw_buttons() {
	k=0
	for ic in btn-light btn-flip btn-view btn-orient btn-exit; do
		bx=$((BX + k * BTN_P))
		fb_rect $BY "$bx" $BTN $BTN BLACK
		fb_rect $((BY + 2)) $((bx + 2)) $((BTN - 4)) $((BTN - 4)) WHITE
		fb_image "$DIR/icons/$ic.png" $((bx + 7)) $((BY + 7)) 38 38
		k=$((k + 1))
	done
}

# Weekday and date, under the divider (the light submenu temporarily covers this row).
draw_date() {
	fb_ltext "$F_REG" 28 $DATE_Y $BX "$(ro_date)"
}

# Light submenu on the date row: Oprit / Minim / Slab / Mediu / Maxim (canvas y MENU_Y..MENU_Y+38,
# Oprit/Minim/Mediu, then Maxim; 108x46 boxes, 114/54 px apart). The current level is shaded.
light_level_now() {
	lipc-get-prop com.lab126.powerd flIntensity 2>/dev/null
}

draw_light_menu() {
	cur=$(light_level_now)
	cur=${cur:-0}
	# Selected box: the last pick if there is one, else the step closest to the level.
	sel=$(cat "$STATE/lightidx" 2>/dev/null)
	if [ -z "$sel" ]; then
		sel=0 best=$cur
		k=2
		for lv in $LIGHT_1 $LIGHT_2 $LIGHT_3; do
			d=$((cur - lv))
			[ "$d" -lt 0 ] && d=$((0 - d))
			if [ "$d" -lt "$best" ]; then
				best=$d sel=$k
			fi
			k=$((k + 1))
		done
	fi
	# Slab (step 2) is no longer in the menu: show it as Minim.
	[ "$sel" = 2 ] && sel=1
	[ "$sel" = 3 ] && sel=2
	[ "$sel" = 4 ] && sel=3
	fb_rect $((MENU_Y - 2)) $((BX - 2)) 348 114 WHITE
	k=0
	for name in $T_LIGHT; do
		x=$((BX + (k % 3) * 114))
		y=$((MENU_Y + (k / 3) * 54))
		fb_rect $y $x 108 46 BLACK
		if [ "$k" = "$sel" ]; then
			fb_rect $((y + 2)) $((x + 2)) 104 42 GRAYD
			fb_text "$F_BOLD" 26 $((y + 8)) $((x + 2)) $((CW - x - 106)) "$name" -O
		else
			fb_rect $((y + 2)) $((x + 2)) 104 42 WHITE
			fb_text "$F_REG" 26 $((y + 8)) $((x + 2)) $((CW - x - 106)) "$name"
		fi
		k=$((k + 1))
	done
	fb_refresh $((MENU_Y - 2)) $((BX - 2)) 348 114
}

# Frontlight steps. Level 0 through powerd leaves the LEDs glowing faintly ("Minim");
# "Oprit" also writes 0 to the lamp driver's own node, which switches them off.
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

# The grid covers part of the weather block, so closing it redraws the screen
# (without flash and without the pause of a layout change).
close_light_menu() {
	rm -f "$STATE/menu"
	touch "$STATE/softdraw"
	kill -USR1 "$main_pid" 2>/dev/null
}

# "Weather first": big current weather, small clock and the touch buttons at the top.
# LAYOUT simple: rain banner and hourly chart when rain is due; weather: the next 5 days.
# Portrait (600x800 canvas) or landscape (800x600), see ORIENT.
draw_weather_first() {
	draw_clock
	draw_buttons
	fb_rect $DIV_Y $DIV_L $DIV_W 3 BLACK
	draw_date
	draw_unit_buttons
	if [ -z "$ST_FETCHED" ]; then
		fb_text "$F_MED" 40 $((CH / 2)) 0 0 "$T_LOADING"
		return 0
	fi
	prepare_now
	if [ "$ORIENT" = landscape ]; then
		draw_weather_landscape
		return 0
	fi
	if [ "$LAYOUT" = simple ] && [ -z "$rain_text" ]; then
		# Dry day, nothing else to show: the weather fills the screen.
		fb_image "$DIR/icons/$ICON.png" 40 190 220 220
		fb_ltext "$F_BOLD" 190 170 290 "$temp"
		fb_ltext "$F_REG" 52 470 40 "$DESC"
		[ -n "$hilo" ] && fb_ltext "$F_REG" 40 550 40 "$hilo" -C GRAY5
		return 0
	fi
	fb_image "$DIR/icons/$ICON.png" 40 166 150 150
	fb_ltext "$F_BOLD" 150 151 220 "$temp"
	fb_ltext "$F_REG" 40 346 40 "$DESC"
	[ -n "$hilo" ] && fb_ltext "$F_REG" 32 400 40 "$hilo" -C GRAY5
	if [ "$LAYOUT" = simple ]; then
		# No forecast list: rain banner and hourly chart when rain is due.
		draw_rain_banner 466
		draw_rain_chart 578 116
	elif [ -n "$rain_text" ]; then
		draw_rain_banner 456
		draw_forecast 516 42 5
	else
		draw_forecast 478 50 5
	fi
}

# Landscape body (800x600 canvas, below the header): weather on the left; on the right the
# rain banner and chart (simple) or the next five days (weather).
draw_weather_landscape() {
	if [ "$LAYOUT" = simple ] && [ -z "$rain_text" ]; then
		fb_image "$DIR/icons/$ICON.png" 70 165 220 220
		fb_ltext "$F_BOLD" 170 145 320 "$temp"
		fb_ltext "$F_REG" 50 425 70 "$DESC"
		[ -n "$hilo" ] && fb_ltext "$F_REG" 36 485 70 "$hilo" -C GRAY5
		return 0
	fi
	fb_image "$DIR/icons/$ICON.png" 48 160 150 150
	fb_ltext "$F_BOLD" 120 154 200 "$temp"
	fb_ltext "$F_REG" 38 330 50 "$DESC"
	[ -n "$hilo" ] && fb_ltext "$F_REG" 32 382 50 "$hilo" -C GRAY5
	if [ "$LAYOUT" = simple ]; then
		# Right: banner (two lines) and the hourly chart.
		draw_rain_banner_box 430 180 340
		draw_rain_chart 304 170
	else
		draw_forecast_col 160 70 5
		[ -n "$rain_text" ] && draw_rain_banner_box 50 438 350
	fi
}

# Status bar inputs: battery level, charging, weather fetch time and whether it is stale.
# Sources $WEATHER_ENV. STATUS_KEY changes exactly when the status bar would look different.
read_status() {
	ST_FETCHED="" ST_OFFLINE=0
	if [ -f "$WEATHER_ENV" ]; then
		. "$WEATHER_ENV"
		ST_FETCHED=$W_FETCHED
		[ $(($(date +%s) - W_FETCHED)) -gt 7200 ] && ST_OFFLINE=1
	fi
	ST_LVL=$(lipc-get-prop com.lab126.powerd battLevel 2>/dev/null)
	ST_CHG=$(lipc-get-prop com.lab126.powerd isCharging 2>/dev/null)
	STATUS_KEY="$ST_LVL $ST_CHG $ST_FETCHED $ST_OFFLINE"
}

# Bottom status bar on the content margins (x 40..560, same as the divider):
# place + weather freshness on the left, battery on the right. Gray, so it stays
# below the clock and weather; the battery turns black at <=20 % when not charging.
# Draws from the last read_status into a cleared area.
draw_status() {
	DRAWN_STATUS=$STATUS_KEY
	footer=$PLACE
	if [ -n "$ST_FETCHED" ]; then
		when=$(date -d "@$ST_FETCHED" '+%H:%M' 2>/dev/null)
		if [ "$ST_OFFLINE" = 1 ]; then
			footer="$PLACE · $T_NODATA $when"
		else
			footer="$PLACE · $T_UPDATED $when"
		fi
	fi
	fb_ltext "$F_REG" 22 $STATUS_TOP $FOOT_L "$footer" -C GRAY5

	lvl=$ST_LVL charging=$ST_CHG
	[ -n "$lvl" ] || return 0
	color=GRAY5
	[ "$charging" != 1 ] && [ "$lvl" -le 20 ] && color=BLACK

	# Outline glyph: 28x14 body + 3x6 nub, right edge at x=560.
	gx=$((STAT_END - 31))
	fill=$((lvl * 20 / 100))
	[ "$fill" -lt 2 ] && fill=2
	fb_rect $((STATUS_TOP + 4)) "$gx" 28 14 "$color"
	fb_rect $((STATUS_TOP + 6)) $((gx + 2)) 24 10 WHITE
	fb_rect $((STATUS_TOP + 8)) $((gx + 4)) "$fill" 6 "$color"
	fb_rect $((STATUS_TOP + 8)) $((gx + 28)) 3 6 "$color"

	# Percentage right-aligned 8 px before the glyph; while charging, a bolt the height of
	# the battery body 5 px before that.
	fb_rtext "$F_REG" 22 $STATUS_TOP $((gx - 8)) "$lvl%" -C "$color"
	if [ "$charging" = 1 ]; then
		fb_image "$DIR/icons/bolt.png" $((RTEXT_LEFT - 14)) $((STATUS_TOP + 4)) 9 14
	fi
}

# Bands redrawn between full redraws (canvas units, full content width): the clock text
# box (its height equals the font px) and the status bar line drawn by draw_status.
set_bands() {
	STATUS_H=22 BTN=53 BTN_P=57
	if [ "$LAYOUT" = weather ] || [ "$LAYOUT" = simple ]; then
		if [ "$ORIENT" = landscape ]; then
			BX=50 BY=26 DIV_Y=106 DIV_L=50 DIV_W=720 DATE_Y=118 MENU_Y=114
			CLOCK_TOP=24 CLOCK_H=72 CLK_L=530 CLK_W=270 CLK_R=770 UNIT_Y=114
			CHART_L=430 CHART_W=340
			STATUS_TOP=547 SB_L=50 SB_R=770
			CITY_X=50 CITY_Y=532 FOOT_L=115
		else
			BX=40 BY=20 DIV_Y=98 DIV_L=40 DIV_W=520 DATE_Y=110 MENU_Y=106
			CLOCK_TOP=20 CLOCK_H=72 CLK_L=326 CLK_W=274 CLK_R=560 UNIT_Y=106
			CHART_L=40 CHART_W=520
			STATUS_TOP=751 SB_L=40 SB_R=560
			CITY_X=40 CITY_Y=736 FOOT_L=105
		fi
		UT_X=$((DIV_L + DIV_W - BTN)) CK_X=$((DIV_L + DIV_W - BTN - BTN_P))
		CITY_W=$BTN CITY_H=$BTN
		LANG_X=$((SB_R - BTN)) LANG_Y=$CITY_Y STAT_END=$((SB_R - BTN - 8))
	else
		CLOCK_TOP=62 CLOCK_H=220 CLK_L=0 CLK_W=600
		CHART_L=40 CHART_W=520
		STATUS_TOP=770 SB_L=40 SB_R=560 FOOT_L=40 STAT_END=560
	fi
}

draw_clock() {
	if [ "$LAYOUT" = weather ] || [ "$LAYOUT" = simple ]; then
		if [ "$CLK12" = 1 ]; then
			ck=$(date '+%I:%M')
			fb_rtext "$F_BOLD" 67 $CLOCK_TOP $((CLK_R - 50)) "${ck#0}"
			fb_ltext "$F_BOLD" 26 $((CLOCK_TOP + 34)) $((CLK_R - 46)) "$(date '+%p')"
		else
			fb_rtext "$F_BOLD" 67 $CLOCK_TOP $CLK_R "$(date '+%H:%M')"
		fi
	else
		fb_text "$F_BOLD" 220 $CLOCK_TOP 0 0 "$(date '+%H:%M')"
	fi
}

# Redraw and refresh only the status bar, and only when its content changed.
refresh_status() {
	read_status
	[ "$STATUS_KEY" = "$DRAWN_STATUS" ] && return 0
	fb_rect $STATUS_TOP $FOOT_L $((STAT_END - FOOT_L)) $STATUS_H WHITE
	draw_status
	fb_refresh $STATUS_TOP $FOOT_L $((STAT_END - FOOT_L)) $STATUS_H
}

# Minute tick between full redraws: clear, redraw and refresh only the clock band, and the
# status bar only when it changed; the rest of the screen is not touched.
draw_partial() {
	fb_rect $CLOCK_TOP $CLK_L $CLK_W $CLOCK_H WHITE
	draw_clock
	fb_refresh $CLOCK_TOP $CLK_L $CLK_W $CLOCK_H
	refresh_status
}

# Current-weather strings shared by the layouts: ICON, DESC, temp, hilo and rain_text.
prepare_now() {
	describe "$W_CODE" "$W_IS_DAY"
	temp="$(tconv "$W_TEMP")°"
	hilo=""
	[ -n "$W_TMAX" ] && [ -n "$W_TMIN" ] && hilo="$(tconv "$W_TMAX")° / $(tconv "$W_TMIN")°"

	# Rain banner text when rain is falling or expected within the lookahead window.
	if [ -n "$WET_NOW" ] || awk -v p="$W_PRECIP" 'BEGIN { exit !(p > 0) }'; then
		word=$T_RAINW
		[ "$WET_NOW" = "Snowing now" ] && word=$T_SNOWW
		if [ -n "$W_RAIN_END" ] && [ "$W_RAIN_AT" = "${W_HOURS%% *}" ]; then
			rain_text="$word $T_UNTIL $W_RAIN_END"
		else
			rain_text="$word $T_NOW"
		fi
	elif [ -n "$W_RAIN_AT" ] && [ -n "$W_RAIN_END" ]; then
		rain_text="$T_RAIN $W_RAIN_AT–$W_RAIN_END"
	elif [ -n "$W_RAIN_AT" ]; then
		rain_text="$T_RAINFROM $W_RAIN_AT"
	else
		rain_text=""
	fi
}

# draw FLASH: redraw and refresh the whole screen (FLASH=1: black flash, clears ghosting).
draw() {
	flash=$1
	read_status

	fbink -q -b -k >/dev/null 2>&1

	if [ "$LAYOUT" = weather ] || [ "$LAYOUT" = simple ]; then
		draw_weather_first
		finish_draw
		return 0
	fi

	fb_text "$F_REG" 34 28 0 0 "$(ro_date)"
	draw_clock
	fb_rect 330 40 520 3 BLACK

	if [ -n "$ST_FETCHED" ]; then
		prepare_now

		if [ "$LAYOUT" = forecast ]; then
			# Forecast: compact weather row, the rain banner when due, then the days.
			draw_now_row
			if [ -n "$rain_text" ]; then
				draw_rain_banner 494
				draw_forecast 574 44 4
			else
				draw_forecast 508 48 5
			fi
		elif [ -n "$rain_text" ]; then
			# Rain: compact weather row, rain banner, hourly chart.
			draw_now_row
			draw_rain_banner 494
			draw_rain_chart 586 120
		else
			# Dry: nothing about rain; the weather grows into the space.
			fb_image "$DIR/icons/$ICON.png" 40 420 200 200
			fb_ltext "$F_BOLD" 160 410 270 "$temp"
			fb_ltext "$F_REG" 36 600 276 "$DESC"
			[ -n "$hilo" ] && fb_ltext "$F_REG" 32 648 276 "$hilo" -C GRAY5
		fi
	else
		fb_text "$F_MED" 40 500 0 0 "$T_LOADING"
	fi

	finish_draw
}

# Status bar, then push everything to the screen (FLASH=1: black flash against ghosting).
finish_draw() {
	rm -f "$STATE/menu"
	draw_status
	if [ "$LAYOUT" = weather ] || [ "$LAYOUT" = simple ]; then
		draw_city_button
		draw_lang_button
	fi
	if [ "$flash" = 1 ]; then
		fbink -q -f -s >/dev/null 2>&1
	else
		fbink -q -s >/dev/null 2>&1
	fi
}

# --- City picker ------------------------------------------------------------
# cities.txt: county|town|latitude|longitude (county "*" = favourites, listed first). The
# chosen city is kept in city.sel (name|lat|lon) and survives restarts.
CITIES=$DIR/cities.txt
CITY_SEL=$DIR/city.sel

load_city() {
	[ -f "$CITY_SEL" ] || return 0
	IFS='|' read -r c_n c_la c_lo <"$CITY_SEL"
	if [ -n "$c_n" ] && [ -n "$c_la" ] && [ -n "$c_lo" ]; then
		PLACE=$c_n LATITUDE=$c_la LONGITUDE=$c_lo
	fi
}

# Button at the bottom left, before the "place · updated" footer.
draw_city_button() {
	fb_rect $CITY_Y $CITY_X $CITY_W $CITY_H BLACK
	fb_rect $((CITY_Y + 2)) $((CITY_X + 2)) $((CITY_W - 4)) $((CITY_H - 4)) WHITE
	fb_image "$DIR/icons/btn-city.png" $((CITY_X + 7)) $((CITY_Y + 7)) 38 38
}

# Unit buttons under the divider, right side: clock format and temperature unit. Each shows
# what a tap switches to.
draw_unit_buttons() {
	if [ "$CLK12" = 1 ]; then ck_lab=24h; else ck_lab=12h; fi
	if [ "$UNIT_T" = F ]; then ut_lab="°C"; else ut_lab="°F"; fi
	for u in "$CK_X|$ck_lab" "$UT_X|$ut_lab"; do
		ux=${u%%|*} ul=${u#*|}
		fb_rect $UNIT_Y $ux $BTN $BTN BLACK
		fb_rect $((UNIT_Y + 2)) $((ux + 2)) $((BTN - 4)) $((BTN - 4)) WHITE
		fb_text "$F_BOLD" 22 $((UNIT_Y + 15)) $((ux + 2)) $((CW - ux - BTN + 2)) "$ul"
	done
}

# Language button at the bottom right, after the battery: shows the language it switches to.
draw_lang_button() {
	fb_rect $LANG_Y $LANG_X $BTN $BTN BLACK
	fb_rect $((LANG_Y + 2)) $((LANG_X + 2)) $((BTN - 4)) $((BTN - 4)) WHITE
	fb_text "$F_BOLD" 22 $((LANG_Y + 15)) $((LANG_X + 2)) $((CW - LANG_X - BTN + 2)) "$T_LANGBTN"
}

# Picker grid: 36 cells a page (3x12 portrait, 4x9 landscape), nav row below.
pk_geom() {
	if [ "$ORIENT" = landscape ]; then
		PK_COLS=4 PK_ROWS=9 PK_GX=50 PK_GY=92 PK_CELLW=172 PK_GAP=4 PK_RH=46
		PK_NAVY=516 PK_ML=50 PK_MW=700
	else
		PK_COLS=3 PK_ROWS=12 PK_GX=40 PK_GY=100 PK_CELLW=170 PK_GAP=5 PK_RH=50
		PK_NAVY=722 PK_ML=40 PK_MW=520
	fi
	PK_PER=$((PK_COLS * PK_ROWS))
	PK_NH=54
}

# Item list of a level into $STATE/pk_items: S|label|name|lat|lon picks a city,
# C|label|county opens a county. Level 0: favourites, then the counties.
pk_build() {
	if [ "$1" = 0 ]; then
		awk -F'|' '/^#/ || NF < 4 { next } $1 == "*" { print "S|" $2 "|" $2 "|" $3 "|" $4 }' "$CITIES"
		awk -F'|' '/^#/ || NF < 4 { next } $1 != "*" && !seen[$1]++ { print "C|" $1 "|" $1 }' "$CITIES"
	else
		awk -F'|' -v c="$2" '/^#/ || NF < 4 { next } $1 == c { print "S|" $2 "|" $2 "|" $3 "|" $4 }' "$CITIES"
	fi >"$STATE/pk_items"
}

# draw_picker FLASH: state is in $STATE/picker (level|county|page|token).
draw_picker() {
	pk_geom
	IFS='|' read -r pk_lvl pk_cty pk_page pk_tok <"$STATE/picker"
	total=$(wc -l <"$STATE/pk_items")
	pages=$(((total + PK_PER - 1) / PK_PER))
	[ "$pages" -lt 1 ] && pages=1
	fbink -q -b -k >/dev/null 2>&1
	if [ "$pk_lvl" = 0 ]; then
		title="$T_PICK"
	else
		title="$pk_cty · $T_PICKTOWN"
	fi
	fb_ltext "$F_BOLD" 30 28 $PK_ML "$title"
	fb_rect 74 $PK_ML $PK_MW 3 BLACK
	first=$((pk_page * PK_PER + 1))
	last=$((first + PK_PER - 1))
	i=0
	sed -n "${first},${last}p" "$STATE/pk_items" >"$STATE/pk_page"
	while IFS='|' read -r typ label rest; do
		x=$((PK_GX + (i % PK_COLS) * (PK_CELLW + PK_GAP)))
		y=$((PK_GY + (i / PK_COLS) * PK_RH))
		ch=$((PK_RH - 4))
		fb_rect $y $x $PK_CELLW $ch BLACK
		if [ "$typ" = S ] && [ "$pk_lvl" = 0 ]; then
			fb_rect $((y + 2)) $((x + 2)) $((PK_CELLW - 4)) $((ch - 4)) GRAYD
			fb_text "$F_BOLD" 20 $((y + (ch - 20) / 2 - 1)) $((x + 2)) $((CW - x - PK_CELLW + 2)) "$label" -O
		else
			fb_rect $((y + 2)) $((x + 2)) $((PK_CELLW - 4)) $((ch - 4)) WHITE
			fb_text "$F_REG" 20 $((y + (ch - 20) / 2 - 1)) $((x + 2)) $((CW - x - PK_CELLW + 2)) "$label"
		fi
		i=$((i + 1))
	done <"$STATE/pk_page"
	# Nav row: back (county level only), page, close.
	nw=$(((PK_MW - 24) / 3))
	k=0
	for nm in back page close; do
		nx=$((PK_ML + k * (nw + 12)))
		lab=""
		case $nm in
		back) [ "$pk_lvl" = 1 ] && lab="$T_BACK" ;;
		page) [ "$pages" -gt 1 ] && lab="$T_PAGE $((pk_page + 1))/$pages" ;;
		*) lab="$T_CLOSE" ;;
		esac
		if [ -n "$lab" ]; then
			fb_rect $PK_NAVY $nx $nw $PK_NH BLACK
			fb_rect $((PK_NAVY + 2)) $((nx + 2)) $((nw - 4)) $((PK_NH - 4)) WHITE
			fb_text "$F_BOLD" 22 $((PK_NAVY + (PK_NH - 22) / 2 - 1)) $((nx + 2)) $((CW - nx - nw + 2)) "$lab"
		fi
		k=$((k + 1))
	done
	if [ "$1" = 1 ]; then
		fbink -q -f -s >/dev/null 2>&1
	else
		fbink -q -s >/dev/null 2>&1
	fi
}

# picker_open LEVEL COUNTY PAGE FLASH (also used for page and level changes).
picker_open() {
	rm -f "$STATE/menu"
	tok=$(date +%s)
	echo "$1|$2|$3|$tok" >"$STATE/picker"
	pk_build "$1" "$2"
	draw_picker "$4"
	# Idle timeout: the dashboard comes back after 90 s without a tap.
	(
		sleep 90
		[ "$(cut -d'|' -f4 "$STATE/picker" 2>/dev/null)" = "$tok" ] && close_picker
	) &
}

close_picker() {
	rm -f "$STATE/picker"
	touch "$STATE/redraw"
	kill -USR1 "$main_pid" 2>/dev/null
}

# Tap in the picker (device px $1 $2).
picker_tap() {
	cx=$((($1 - OX) * 1000 / S))
	cy=$((($2 - OY) * 1000 / S))
	pk_geom
	IFS='|' read -r pk_lvl pk_cty pk_page pk_tok <"$STATE/picker"
	total=$(wc -l <"$STATE/pk_items")
	pages=$(((total + PK_PER - 1) / PK_PER))
	[ "$cx" -lt $((PK_ML - 10)) ] && return 0
	if [ "$cy" -ge $((PK_NAVY - 8)) ]; then
		nw=$(((PK_MW - 24) / 3))
		k=$(((cx - PK_ML) / (nw + 12)))
		case $k in
		0) [ "$pk_lvl" = 1 ] && picker_open 0 "" 0 0 ;;
		1) [ "$pages" -gt 1 ] && picker_open "$pk_lvl" "$pk_cty" $(((pk_page + 1) % pages)) 0 ;;
		*) close_picker ;;
		esac
		return 0
	fi
	[ "$cy" -ge "$PK_GY" ] || return 0
	col=$(((cx - PK_GX) / (PK_CELLW + PK_GAP)))
	row=$(((cy - PK_GY) / PK_RH))
	[ "$col" -lt "$PK_COLS" ] && [ "$row" -lt "$PK_ROWS" ] || return 0
	idx=$((pk_page * PK_PER + row * PK_COLS + col + 1))
	line=$(sed -n "${idx}p" "$STATE/pk_items")
	[ -n "$line" ] || return 0
	typ=$(echo "$line" | cut -d'|' -f1)
	a=$(echo "$line" | cut -d'|' -f3)
	if [ "$typ" = S ]; then
		b=$(echo "$line" | cut -d'|' -f4)
		c=$(echo "$line" | cut -d'|' -f5)
		printf '%s|%s|%s\n' "$a" "$b" "$c" >"$CITY_SEL"
		log "city: $a $b $c"
		touch "$STATE/refetch"
		close_picker
	else
		picker_open 1 "$a" 0 0
	fi
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

# Touch buttons (5, from BX): light, flip, view, orientation, exit. Each loop opens the
# device afresh, so the rest of a tap's events are dropped while sleeping. The panel does
# not follow the screen rotation, so raw coordinates are mapped to the current screen:
# d = quarter turns from the native rotation (0 as is, 2 mirrored, 1 and 3 swap axes).
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
			rota=$(cat "$STATE/rota" 2>/dev/null)
			layout_init
			load_lang
			d=$(((${rota:-$NATIVE_ROTA} - NATIVE_ROTA + 4) % 4))
			case $d in
			0) tx=$rx ty=$ry ;;
			1) tx=$ry ty=$((SCR_H - rx)) ;;
			2) tx=$((SCR_W - rx)) ty=$((SCR_H - ry)) ;;
			*) tx=$((SCR_W - ry)) ty=$rx ;;
			esac
			log "tap $rx,$ry -> $tx,$ty ($ORIENT, rotation ${rota:-?})"
			bz=$(px_len $BTN_P)
			bx0=$(px_x $((BX - 4)))
			if [ -f "$STATE/picker" ]; then
				picker_tap "$tx" "$ty"
			elif [ "$ty" -ge "$(px_y $((CITY_Y - 14)))" ] && [ "$tx" -ge "$(px_x $((CITY_X - 10)))" ] && [ "$tx" -lt "$(px_x $((CITY_X + CITY_W + 40)))" ]; then
				picker_open 0 "" 0 1
			elif [ "$ty" -ge "$(px_y $((LANG_Y - 14)))" ] && [ "$tx" -ge "$(px_x $((LANG_X - 30)))" ]; then
				if [ "$UI_LANG" = en ]; then echo ro >"$LANG_SEL"; else echo en >"$LANG_SEL"; fi
				touch "$STATE/redraw"
				kill -USR1 "$main_pid" 2>/dev/null
			elif [ ! -f "$STATE/menu" ] && [ "$ty" -ge "$(px_y $((UNIT_Y - 6)))" ] && [ "$ty" -lt "$(px_y $((UNIT_Y + BTN + 12)))" ] && [ "$tx" -ge "$(px_x $((CK_X - 6)))" ]; then
				if [ "$tx" -ge "$(px_x $((UT_X - 3)))" ]; then
					if [ "$UNIT_T" = F ]; then echo C >"$DIR/temp.sel"; else echo F >"$DIR/temp.sel"; fi
				elif [ "$CLK12" = 1 ]; then
					echo 24 >"$DIR/clock.sel"
				else
					echo 12 >"$DIR/clock.sel"
				fi
				touch "$STATE/redraw"
				kill -USR1 "$main_pid" 2>/dev/null
			elif [ -f "$STATE/menu" ] && [ "$ty" -ge "$(px_y $((MENU_Y - 2)))" ] && [ "$ty" -lt "$(px_y $((MENU_Y + 108)))" ] && [ "$tx" -ge "$(px_x $BX)" ] && [ "$tx" -lt "$(px_x $((BX + 342)))" ]; then
				# Light submenu: row 1 Oprit / Minim / Mediu, row 2 Maxim.
				col=$(((tx - $(px_x $BX)) / $(px_len 114)))
				[ "$col" -gt 2 ] && col=2
				row=$(((ty - $(px_y $((MENU_Y - 2)))) / $(px_len 54)))
				if [ "$row" -ge 1 ]; then idx=4
				elif [ "$col" = 2 ]; then idx=3
				else idx=$col; fi
				light_set "$idx"
				close_light_menu
			elif [ "$ty" -lt "$(px_y $((BY + BTN + 8)))" ] && [ "$tx" -ge "$bx0" ] && [ "$tx" -lt $((bx0 + bz * 5 + 4)) ]; then
				idx=$(((tx - bx0) / bz))
				[ "$idx" -gt 4 ] && idx=4
				case $idx in
				0)
					if [ -f "$STATE/menu" ]; then
						close_light_menu
					else
						tok=$(date +%s)
						echo "$tok" >"$STATE/menu"
						draw_light_menu
						(
							sleep 8
							[ "$(cat "$STATE/menu" 2>/dev/null)" = "$tok" ] && close_light_menu
						) &
					fi
					;;
				1)
					# Flip 180 degrees: portrait native/upside down, landscape 0/2.
					if [ "$ORIENT" = landscape ]; then
						if [ "${rota:-0}" = 0 ]; then nr=2; else nr=0; fi
					elif [ "${rota:-$NATIVE_ROTA}" = "$NATIVE_ROTA" ]; then
						nr=$(((NATIVE_ROTA + 2) % 4))
					else
						nr=$NATIVE_ROTA
					fi
					set_rota "$nr"
					touch "$STATE/redraw"
					kill -USR1 "$main_pid" 2>/dev/null
					;;
				2)
					# View: switch between the simple and the 5-day layout.
					if [ "$(cat "$LAYOUT_FILE" 2>/dev/null)" = weather ]; then
						echo simple >"$STATE/layoutreq"
						echo simple >"$LAYOUT_FILE"
					else
						echo weather >"$STATE/layoutreq"
						echo weather >"$LAYOUT_FILE"
					fi
					touch "$STATE/redraw"
					kill -USR1 "$main_pid" 2>/dev/null
					;;
				3)
					# Orientation: portrait <-> landscape.
					if [ "$ORIENT" = landscape ]; then
						echo portrait >"$STATE/orient"
						set_rota "$NATIVE_ROTA"
					else
						echo landscape >"$STATE/orient"
						set_rota "$LANDSCAPE_ROTA"
					fi
					touch "$STATE/redraw"
					kill -USR1 "$main_pid" 2>/dev/null
					;;
				*)
					kill -TERM "$main_pid" 2>/dev/null
					return 0
					;;
				esac
			fi
		fi
		sleep 1
	done
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
	log "start ($LAYOUT layout, $ORIENT)"

	WATCH_PID=""
	EVENT_PID=""
	SLEEP_PID=""
	trap 'shutdown' TERM INT HUP
	# Power events (charger plugged/unplugged, battery level) redraw the status bar now
	# rather than at the next minute tick.
	trap ':' USR1

	NATIVE_ROTA=$(cat /sys/class/graphics/fb0/rotate 2>/dev/null)
	rm -f "$STATE/redraw" "$STATE/softdraw" "$STATE/layoutreq" "$STATE/lightidx" "$STATE/picker" "$STATE/refetch"
	load_city
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
	log "light: powerd $(light_level_now) nodes: $(ls -d /sys/class/backlight/* /sys/devices/system/fl_* 2>&1 | tr '\n' ' ')"
	log "services: $(initctl list 2>/dev/null | grep -i -e pillow -e gui -e framework | tr '\n' ';')"

	# Touch buttons: see touch_watch.
	main_pid=$$
	case "$LAYOUT" in
	weather | simple)
		touch_watch &
		;;
	*)
		# Layouts without buttons: any tap exits.
		(
			dd if="$(touch_device)" bs=16 count=1 >/dev/null 2>&1 &&
				log "tap: exit" &&
				kill -TERM "$main_pid" 2>/dev/null
		) &
		;;
	esac
	WATCH_PID=$!

	# powerd broadcasts charging, notCharging, USBPlugin, USBUnplug and battLevelChanged;
	# on any of them, poke the main loop to re-read the status.
	(
		lipc-wait-event -m com.lab126.powerd '*' 2>/dev/null |
			while read -r _; do kill -USR1 "$main_pid" 2>/dev/null || break; done
	) &
	EVENT_PID=$!

	last_fetch=0
	last_ntp=0
	first=1
	last_day=""
	while :; do
		set -- $(date '+%s %M %j')
		now=$1 min=${2#0} today=$3

		# Full redraw (with flash) at start and every FULL_REFRESH_MINUTES; full redraw
		# for the new date after midnight; otherwise only the clock and changed status bar.
		if [ -f "$STATE/picker" ]; then
			:
		elif [ "$first" = 1 ] || [ $((min % FULL_REFRESH_MINUTES)) -eq 0 ]; then
			draw 1
		elif [ "$today" != "$last_day" ]; then
			draw 0
		else
			draw_partial
		fi
		last_day=$today
		first=0

		if [ $((now - last_fetch)) -ge $((WEATHER_MINUTES * 60 - 30)) ]; then
			if fetch_weather; then
				last_fetch=$now
				[ -f "$STATE/picker" ] || draw 0
			fi
		fi

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
					rm -f "$STATE/refetch" "$WEATHER_ENV"
					load_city
					fbink -q -c -m -M -t regular="$F_MED",px=36 "$T_LOADING" >/dev/null 2>&1
					if fetch_weather; then last_fetch=$(date +%s); else last_fetch=0; fi
				fi
				sleep 1
				layout_init
				draw 1
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

# Orientation argument: portrait (default) or landscape (weather and simple layouts only).
orient_arg() {
	case "${1:-portrait}" in
	landscape) echo landscape ;;
	*) echo portrait ;;
	esac
}

# Layout argument for start/run: simple (default), weather, simplistic or forecast.
layout_arg() {
	case "${1:-simple}" in
	simplistic | forecast | weather | simple) echo "${1:-simple}" ;;
	*)
		echo "unknown layout '$1' (use simplistic, forecast, weather or simple)" >&2
		exit 2
		;;
	esac
}

case "$1" in
start)
	layout=$(layout_arg "$2") || exit 2
	if is_running; then
		echo "rekindle already running"
		exit 0
	fi
	mkdir -p "$STATE"
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
		echo "rekindle not running"
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
	case "$LAYOUT" in
	weather | simple) ;;
	*) ORIENT=portrait ;;
	esac
	run
	;;
fetch)
	fetch_weather && cat "$WEATHER_ENV"
	;;
*)
	echo "usage: $0 start [simplistic|forecast|weather|simple] [portrait|landscape]|stop|status|run [...]|fetch" >&2
	exit 2
	;;
esac
