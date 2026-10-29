package ro.meteoalarm.android.core;

import java.util.Calendar;
import java.util.List;

/**
 * The portrait screen of Meteo Alarm Kindle, laid out for a tall phone. The canvas is 758 units
 * wide like the Paperwhite's; the height follows the phone (at least BASE_H) and the extra room
 * goes to the current weather. From the top: clock, city and warnings, the temperature and icon,
 * the precipitation chart, tomorrow and the day after, three more days, sun / UV / pollen and the
 * status line.
 */
public final class Screen {
	public static final float W = 758, BASE_H = 1538;

	// Inputs.
	public Weather w;
	public List<Warnings.Warn> warns;
	public int pollenLvl = -1;
	public String pollenPlant = "";
	public Cities.City city;
	public Texts T = new Texts(false);
	public boolean unitF, clk12;
	public Calendar now = Calendar.getInstance();
	public int batt = -1;
	public boolean charging, busy, offline;
	public long fetched;
	public String error = "";

	// Buttons (x, y, w, h in canvas units), set by draw.
	public final float[] btnMenu = { 40, 24, 64, 64 }, btnRefresh = { 654, 24, 64, 64 }, btnCity = { 40, 0, 64, 64 };
	public float cityTop = 104, cityBottom = 160;

	private Gfx g;

	// Middle of the weather icon's drawing inside its 200 x 200 file (icons/centru.txt).
	private static final String[] CENTRE = { "clear-day 24 24 177 177", "clear-night 38 38 144 163", "cloudy 26 59 174 136",
			"drizzle 26 21 174 158", "fog 25 28 176 176", "partly-day 8 8 183 157", "partly-night 31 24 183 157",
			"rain 26 17 174 179", "snow 26 17 174 182", "thunder 26 17 174 197" };

	public void draw(Gfx gfx, float ch) {
		g = gfx;
		g.rect(0, 0, W, ch, Gfx.WHITE);
		button(btnMenu);
		for (int k = 0; k < 3; k++) g.rect(57, 41 + k * 13, 30, 4, Gfx.BLACK);
		button(btnRefresh);
		g.arc(686, 56, 15, -50, 290, 4, Gfx.BLACK);
		// Arrowhead at the arc's start (upper right), pointing along the circle.
		g.poly(new float[] { 690, 33, 705, 46, 689, 52 }, Gfx.BLACK);
		drawClock();
		rtext(false, 26, 71, 641, T.date(now), Gfx.BLACK);

		float fb = ch - 76;
		btnCity[1] = fb;
		if (w == null) {
			g.rect(40, 102, 678, 2, Gfx.BLACK);
			String msg = error.length() > 0 ? error : T.loading;
			float p = fit(true, 40, 640, msg);
			ctext(true, p, 300, W / 2, msg, Gfx.BLACK);
			footer(fb);
			return;
		}

		String label = city.label();
		ltext(true, fit(true, 36, 340, label), 116, 40, label, Gfx.BLACK);

		float nowBot = 498 + Math.max(0, ch - BASE_H);
		float fy = nowBot - 4;
		int shown = drawWarnings();
		g.rect(40, 102, hdrEnd - 40, 2, Gfx.BLACK);

		String[] d = T.describe(w.code, w.isDay);
		if (shown == 0) {
			drawNowSide(d[0], 40, 104, 718, fy + 4);
		} else {
			float base = nowBot - 21;
			drawTemp(40, base, 252, 405);
			float cy = base - tp * 32 / 100;
			icLeft = tempEnd + 2; icRight = 748; icTop = warnBot + 4; icFit = true; icBot = fy - 6;
			drawIconC(d[0], (tempEnd + 718) / 2, cy, 260, cy - warnBot - 10, 718 - tempEnd - 16);
			icTop = 0; icFit = false;
		}

		// Description and wind on the right, "feels like" and high / low on the left.
		rtext(true, fit(true, 39, 330, d[1]), fy, 712, d[1], Gfx.BLACK);
		if (!Double.isNaN(w.wind)) {
			String wind = unitF ? T.wind + " " + Math.round(w.wind * 0.621371) + " mph" : T.wind + " " + Math.round(w.wind) + " km/h";
			rtext(false, 30, fy + 40, 712, upper(wind), Gfx.BLACK);
		}
		if (!Double.isNaN(w.feels)) ltext(false, 30, fy + 7, 40, upper(T.feels + " " + t(w.feels) + "°"), Gfx.BLACK);
		if (!Double.isNaN(w.tmax) && !Double.isNaN(w.tmin))
			ltext(false, 30, fy + 40, 40, upper(T.hi + " " + t(w.tmax) + "° / " + T.lo + " " + t(w.tmin) + "°"), Gfx.BLACK);

		float y0 = fy + 80;
		drawPrecipBox(40, y0, 678, 300, 46);
		drawDayCard(40, y0 + 314, 0, T.day1);
		drawDayCard(387, y0 + 314, 1, T.day2);
		drawDayCols(2, y0 + 526);
		drawSunBox(40, y0 + 690, 678, 184);
		footer(fb);
	}

	// --- Helpers ---------------------------------------------------------------------

	private String t(double c) {
		long v = Math.round(unitF ? c * 9 / 5 + 32 : c);
		return Long.toString(v);
	}

	private static String upper(String s) {
		return s.toUpperCase();
	}

	private void button(float[] b) {
		g.roundRect(b[0], b[1], b[2], b[3], 10, Gfx.BLACK);
		g.roundRect(b[0] + 2, b[1] + 2, b[2] - 4, b[3] - 4, 8, Gfx.WHITE);
	}

	private void ltext(boolean bold, float px, float top, float left, String s, int color) {
		g.text(bold, px, top, left, s, color);
	}

	/** Right edge at RIGHT; returns the left edge. */
	private float rtext(boolean bold, float px, float top, float right, String s, int color) {
		float x = right - g.width(bold, px, s);
		g.text(bold, px, top, x, s, color);
		return x;
	}

	private void ctext(boolean bold, float px, float top, float cx, String s, int color) {
		g.text(bold, px, top, cx - g.width(bold, px, s) / 2, s, color);
	}

	/** The largest size up to PX at which S fits in MAXW. */
	private float fit(boolean bold, float px, float maxw, String s) {
		while (px > 14 && g.width(bold, px, s) > maxw) px = px * 92 / 100;
		return px;
	}

	/** Box title in a gray header band: capitals at about 3/4 of the band, drawn twice 1 unit apart. */
	private void head(float top, float h, float cx, float maxw, String s, float px) {
		float p = fit(true, px > 0 ? px : (h - 4) * 76 / 100, maxw - 1, s);
		float x = cx - g.width(true, p, s) / 2, y = top + h / 2 - p * 485 / 1000;
		g.text(true, p, y, x, s, Gfx.BLACK);
		g.text(true, p, y, x + 1, s, Gfx.BLACK);
	}

	/** Frame with rounded corners, a 2-unit outline and a gray header band HD high. */
	private void box(float x, float y, float w, float h, float hd) {
		float r = 14;
		g.roundRect(x, y, w, h, r, Gfx.BLACK);
		g.roundRect(x + 2, y + 2, w - 4, h - 4, r - 2, Gfx.GRAYD);
		g.rect(x + 2, y + hd, w - 4, h - hd - r - 2, Gfx.WHITE);
		g.roundRect(x + 2, y + h - 2 * r - 2, w - 4, 2 * r, r - 2, Gfx.WHITE);
		g.rect(x + 2, y + hd - 2, w - 4, 2, Gfx.BLACK);
	}

	private void drawClock() {
		int h = now.get(Calendar.HOUR_OF_DAY), m = now.get(Calendar.MINUTE);
		float right = 635;
		if (clk12) {
			String pm = h < 12 ? "AM" : "PM";
			int h12 = h % 12 == 0 ? 12 : h % 12;
			float pw = g.width(true, 22, pm);
			rtext(true, 50, 17, right - pw - 4, h12 + String.format(":%02d", m), Gfx.BLACK);
			ltext(true, 22, 17 + 50 * 81 / 100 - 18, right - pw, pm, Gfx.BLACK);
		} else {
			rtext(true, 50, 17, right, String.format("%02d:%02d", h, m), Gfx.BLACK);
		}
	}

	// --- Current weather ---------------------------------------------------------------

	private float icLeft = 0, icRight = 758, icTop = 0, icBot = 0, icPct = 100;
	private boolean icFit;

	private void drawIcon(String icon, float x, float y, float s) {
		g.image("icons/" + icon + ".png", x, y, s, s);
	}

	/**
	 * The icon with the middle of its drawing at CX CY, as large as fits: at most SIZE, the
	 * drawing at most HALF_H above and below CY and MAXW wide.
	 */
	private void drawIconC(String icon, float cx, float cy, float size, float halfH, float maxw) {
		float x0 = 0, y0 = 0, x1 = 200, y1 = 200;
		for (String c : CENTRE) {
			String[] p = c.split(" ");
			if (p[0].equals(icon)) {
				x0 = Float.parseFloat(p[1]); y0 = Float.parseFloat(p[2]); x1 = Float.parseFloat(p[3]); y1 = Float.parseFloat(p[4]);
			}
		}
		float s = size, dh = y1 - y0, dw = x1 - x0;
		if (s * dh / 200 > halfH * 2) s = halfH * 2 * 200 / dh;
		if (s * dw / 200 > maxw) s = maxw * 200 / dw;
		s = s * icPct / 100;
		if (icFit && cy - s * (y0 + y1) / 400 < icTop && icTop + s * y1 / 200 > icBot) s = (icBot - icTop) * 200 / y1;
		float x = cx - s * (x0 + x1) / 400;
		if (x < icLeft) x = icLeft;
		if (x + s > icRight) x = icRight - s;
		float y = cy - s * (y0 + y1) / 400;
		if (y < icTop) y = icTop;
		drawIcon(icon, x, y, s);
	}

	// Measured temperature: size, minus, digits, unit.
	private float tp, tMw, tWn, tGap, tWu, tU, tW, tempEnd;
	private boolean tNeg;
	private String tN;

	private void tempSize(float px, float maxw) {
		tN = t(w.temp);
		tNeg = tN.startsWith("-");
		if (tNeg) tN = tN.substring(1);
		tp = px;
		while (true) {
			tU = tp * 43 / 100;
			tWn = g.width(true, tp, tN);
			tWu = g.width(true, tU, unitF ? "F" : "C");
			tGap = tp / 25;
			tMw = tNeg ? tp * 64 * 42 / 10000 : 0;
			tW = tMw + tWn + tGap + tWu;
			if (tW <= maxw || tp < 60) break;
			tp = tp * 94 / 100;
		}
	}

	private void drawTemp(float left, float base, float px, float maxw) {
		tempSize(px, maxw);
		drawTempAt(left, base);
	}

	/** Minus bar, digits, a small "°" level with their top and the unit on their baseline. */
	private void drawTempAt(float left, float base) {
		float dh = tp * 64 / 100, x = left;
		if (tNeg) {
			float mt = Math.max(4, dh * 75 / 1000);
			g.rect(x, base - dh / 2 - mt / 2, dh * 30 / 100, mt, Gfx.BLACK);
			x += tMw;
		}
		g.text(true, tp, base - tp * 81 / 100, x, tN, Gfx.BLACK);
		x += tWn + tGap;
		g.text(true, tU, base - dh - tU * 17 / 100, x, "°", Gfx.BLACK);
		g.text(true, tU, base - tU * 81 / 100, x, unitF ? "F" : "C", Gfx.BLACK);
		tempEnd = x + tWu;
	}

	/** No warnings: the temperature right-aligned on the middle, the icon centred in the right half. */
	private void drawNowSide(String icon, float l, float top, float r, float bot) {
		float mid = (l + r) / 2, cy = (top + bot) / 2 + 20, hw = (r - l) / 2;
		icLeft = mid + 2; icRight = r; icPct = 100; icTop = top + 60;
		drawIconC(icon, mid + hw / 2, cy, 320, (bot - top) / 2 - 40, hw - 30);
		icTop = 0;
		tempSize(252, hw - 12);
		float dh = tp * 64 / 100;
		drawTempAt(mid + 2 - tW, cy + dh / 2);
	}

	// --- Warnings ------------------------------------------------------------------------

	private float hdrEnd = 718, warnBot = 102;

	/** Up to two warnings right-aligned under the clock; returns how many were drawn. */
	private int drawWarnings() {
		hdrEnd = 718;
		warnBot = 102;
		if (warns == null) return 0;
		float wy = 102;
		int shown = 0;
		long nowMs = now.getTimeInMillis();
		for (Warnings.Warn wr : warns) {
			if (wr.until <= nowMs || shown >= 2) continue;
			String name = T.warn[Math.min(3, Math.max(1, wr.level)) - 1];
			String lab = T.en ? name + " " + T.warnCode : T.warnCode + " " + name;
			String txt = T.warnType(wr.type);
			String per = T.weekdayTime(wr.from, clk12) + " – " + T.weekdayTime(wr.until, clk12);
			float lp = fit(true, 39, 330, lab);
			float bw = g.width(true, lp, lab) + 14;
			float txp = fit(false, 31, 330, txt);
			int fill = wr.level >= 2 ? Gfx.GRAYA : Gfx.GRAYD;
			float sx = 718 - bw;
			if (wr.level >= 3) {
				sx -= 56;
				g.image("ui/atentie.png", sx, wy, 46, 42);
			}
			if (shown == 0) hdrEnd = sx - 6;
			g.roundRect(718 - bw, wy, bw, 42, 12, Gfx.BLACK);
			g.roundRect(718 - bw + 2, wy + 2, bw - 4, 38, 10, fill);
			ltext(true, lp, wy + (42 - lp) / 2, 718 - bw + 7, lab, Gfx.BLACK);
			rtext(false, txp, wy + 50, 716, txt, Gfx.BLACK);
			rtext(false, 30, wy + 79, 712, per, Gfx.GRAY5);
			wy += 116;
			warnBot = wy - 6;
			shown++;
		}
		return shown;
	}

	// --- Precipitation -------------------------------------------------------------------

	private String rainText() {
		boolean snowNow = Weather.snowCode(w.code);
		if (w.wetNow() || w.precip > 0) {
			String word = snowNow ? T.snowW : T.rainW;
			if (w.rainEnd.length() > 0 && !w.hours.isEmpty() && w.rainAt.equals(w.hours.get(0)))
				return word + " " + T.until + " " + Texts.clock(w.rainEnd, clk12);
			return word + " " + T.now;
		}
		String word = w.snowMaj ? T.snow : T.rain, from = w.snowMaj ? T.snowFrom : T.rainFrom;
		if (w.rainAt.length() > 0 && w.rainEnd.length() > 0)
			return word + " " + Texts.clock(w.rainAt, clk12) + "–" + Texts.clock(w.rainEnd, clk12);
		if (w.rainAt.length() > 0) return from + " " + Texts.clock(w.rainAt, clk12);
		return "";
	}

	private void drawPrecipBox(float pl, float pt, float pw, float ph, float phd) {
		boolean snow = w.snowMaj || ((w.wetNow() || w.precip > 0) && Weather.snowCode(w.code));
		box(pl, pt, pw, ph, phd);
		head(pt, phd, pl + pw / 2, pw - 40, (snow ? T.snowUp : T.rainUp) + " · " + T.next12, 0);
		String rt = rainText();
		if (rt.length() > 0) ltext(true, 36, pt + 63, pl + 22, rt, Gfx.BLACK);
		else ltext(true, 36, pt + 63, pl + 22, T.noPrecip, Gfx.GRAY5);
		rtext(false, 29, pt + 68, pl + pw - 20, T.max + " " + w.rainMaxP + "%", Gfx.GRAY5);
		boolean leg = false;
		for (boolean s : w.snowy) leg |= s;
		if (leg) {
			drawLegend(pl + 20, pt + 104);
			drawChart(pl + 16, pw - 34, pt + 152, ph - 198);
		} else {
			drawChart(pl + 16, pw - 34, pt + 120, ph - 166);
		}
	}

	private void drawLegend(float x, float y) {
		int[] cs = { Gfx.GRAY5, Gfx.BLACK, Gfx.GRAYA };
		String[] ls = { T.legSnow, T.legRain, T.legDry };
		for (int k = 0; k < 3; k++) {
			g.rect(x, y, 16, 16, cs[k]);
			ltext(false, 20, y - 2, x + 23, ls[k], Gfx.GRAY5);
			x += 23 + g.width(false, 20, ls[k]) + 22;
		}
	}

	/** One bar per hour, height = probability: black rain, dark gray snow, light gray dry. */
	private void drawChart(float cl, float cw, float ct, float ch) {
		int n = w.probs.length;
		if (n == 0) return;
		float pitch = (float) Math.floor(cw / n), bw = pitch * 85 / 100;
		float ty = ct + ch - Weather.RAIN_PROBABILITY * ch / 100;
		for (float x = cl; x < cl + cw; x += 10) g.rect(x, ty, 5, 2, Gfx.GRAY5);
		for (int k = 0; k < n; k++) {
			float bh = Math.max(4, w.probs[k] * ch / 100);
			int color = !w.wet[k] ? Gfx.GRAYA : w.snowy[k] ? Gfx.GRAY5 : Gfx.BLACK;
			float x = cl + k * pitch + (pitch - bw) / 2;
			g.rect(x, ct + ch - bh, bw, bh, color);
			if (k % 3 == 0) ltext(false, 23, ct + ch + 8, x, Texts.clock(w.hours.get(k), clk12), Gfx.GRAY5);
		}
		// "acum" over the chart where the current time falls, and a dotted line down to the bar.
		String first = w.hours.get(0);
		if (first.length() < 2) return;
		int o = (now.get(Calendar.HOUR_OF_DAY) - Integer.parseInt(first.substring(0, 2)) + 24) % 24;
		if (o >= n) return;
		float nx = cl + o * pitch + now.get(Calendar.MINUTE) * pitch / 60;
		g.poly(new float[] { nx - 8, ct - 8, nx + 8, ct - 8, nx, ct + 3 }, Gfx.BLACK);
		ctext(true, 15, ct - 25, nx, T.nowMark, Gfx.BLACK);
		float end = ct + ch - Math.max(4, w.probs[o] * ch / 100) - 2;
		for (float y = ct + 6; y < end; y += 10) g.rect(nx - 1, y, 2, Math.min(6, end - y), Gfx.BLACK);
	}

	// --- Next days ---------------------------------------------------------------------

	/** Tomorrow / the day after: title, icon, big high, gray "/ low", description. */
	private void drawDayCard(float left, float top, int k, String title) {
		box(left, top, 331, 198, 52);
		head(top, 52, left + 165, 290, title, 0);
		if (k >= w.dayDates.size()) return;
		String[] d = T.describe(w.dayCodes.get(k), true);
		String hi = t(w.dayHi.get(k)) + "°", lo = "/ " + t(w.dayLo.get(k)) + "°";
		float hp = 93, lp, wh, wl;
		while (true) {
			lp = hp / 2;
			wh = g.width(true, hp, hi);
			wl = g.width(false, lp, lo);
			if (84 + wh + 4 + wl <= 311 || hp < 50) break;
			hp = hp * 94 / 100;
		}
		float gx = Math.max(left + 8, left + (331 - 84 - wh - 4 - wl) / 2);
		drawIcon(d[0], gx - 10, top + 67, 92);
		ltext(true, hp, top + 51 + (93 - hp) * 81 / 100, gx + 84, hi, Gfx.BLACK);
		ltext(false, lp, top + 90 + (47 - lp) * 81 / 100, gx + 84 + wh + 4, lo, Gfx.GRAY5);
		ctext(false, fit(false, 30, 310, d[1]), top + 160, left + 165, d[1], Gfx.BLACK);
	}

	/** Three more days: weekday and date, icon, high / low, chance of rain. */
	private void drawDayCols(int first, float top) {
		for (int c = 0; c < 3; c++) {
			float x = 40 + c * 231.5f;
			box(x, top, 215, 150, 44);
			int k = first + c;
			if (k >= w.dayDates.size()) continue;
			float cx = x + 107.5f;
			head(top, 44, cx, 190, T.weekdayUp(w.dayDates.get(k), true), 0);
			drawIcon(T.describe(w.dayCodes.get(k), true)[0], cx - 30, top + 46, 60);
			String s = t(w.dayHi.get(k)) + "° / " + t(w.dayLo.get(k)) + "°";
			float p = fit(true, 36, 190, s);
			ctext(true, p, top + 104 + (36 - p) * 6 / 10, cx, s, Gfx.BLACK);
		}
	}

	// --- Sun, UV, pollen -------------------------------------------------------------------

	private void scale(float x, float y, int n, int filled, float bw) {
		for (int k = 0; k < n; k++) {
			float sx = x + k * (bw + 4);
			g.rect(sx, y, bw, 10, Gfx.BLACK);
			if (k >= filled) g.rect(sx + 2, y + 2, bw - 4, 6, Gfx.WHITE);
		}
	}

	private void drawSunBox(float x, float top, float w3, float h) {
		box(x, top, w3, h, 46);
		float c1 = x + w3 / 6, c2 = x + w3 / 2, c3 = x + w3 * 5 / 6;
		float p = 31;
		for (String s : new String[] { T.sun, T.uvT, T.pollen }) p = fit(true, p, 200, s);
		head(top, 46, c1, 200, T.sun, p);
		head(top, 46, c2, 200, T.uvT, p);
		head(top, 46, c3, 200, T.pollen, p);
		for (float dx : new float[] { x + w3 / 3, x + w3 * 2 / 3 }) g.rect(dx - 1, top + 60, 2, h - 76, Gfx.GRAYA);
		ctext(false, 20, top + 54, c1, T.sunrise, Gfx.BLACK);
		ctext(true, 29, top + 78, c1, Texts.clock(this.w.sunrise, clk12), Gfx.BLACK);
		ctext(false, 20, top + 121, c1, T.sunset, Gfx.BLACK);
		ctext(true, 29, top + 145, c1, Texts.clock(this.w.sunset, clk12), Gfx.BLACK);
		int uv = this.w.uv;
		if (uv >= 0) {
			int l = uv <= 2 ? 1 : uv <= 5 ? 2 : uv <= 7 ? 3 : uv <= 10 ? 4 : 5;
			ctext(true, 74, top + 50, c2, Integer.toString(uv), Gfx.BLACK);
			ctext(false, 22, top + 128, c2, T.uvLv[l - 1], Gfx.BLACK);
			scale(c2 - 60, top + 162, 5, l, 21);
		} else {
			ctext(true, 74, top + 50, c2, "–", Gfx.BLACK);
			scale(c2 - 60, top + 162, 5, 0, 21);
		}
		if (pollenLvl > 0) {
			ctext(true, 29, top + 62, c3, T.polLv[pollenLvl - 1], Gfx.BLACK);
			ctext(false, 22, top + 103, c3, pollenPlant.length() > 0 ? T.plant(pollenPlant) : T.noPollen, Gfx.BLACK);
		} else {
			ctext(true, 29, top + 62, c3, "–", Gfx.BLACK);
			ctext(false, 22, top + 103, c3, T.noData2, Gfx.BLACK);
		}
		scale(c3 - 60, top + 162, 4, Math.max(0, pollenLvl), 27);
	}

	// --- Status line -----------------------------------------------------------------------

	private void footer(float fb) {
		button(btnCity);
		g.image("icons/btn-city.png", 56, fb + 16, 32, 32);
		float batLeft = 718;
		float gy = fb + 22;
		if (batt >= 0) {
			float gx = 718 - 44;
			g.rect(gx, gy, 40, 20, Gfx.BLACK);
			g.rect(gx + 2, gy + 2, 36, 16, Gfx.WHITE);
			g.rect(gx + 5, gy + 5, Math.max(2, batt * 30 / 100), 10, Gfx.BLACK);
			g.rect(gx + 40, gy + 6, 4, 8, Gfx.BLACK);
			batLeft = rtext(true, 26, gy - 4, gx - 7, batt + "%", Gfx.BLACK);
			if (charging) {
				g.image("icons/bolt.png", batLeft - 16, gy + 2, 11, 17);
				batLeft -= 16;
				float mp = fit(true, 26, batLeft - 10 - 330, T.charging);
				batLeft = rtext(true, mp, gy - 4 + (26 - mp) * 81 / 100, batLeft - 10, T.charging, Gfx.BLACK);
			}
		}
		String upd = "";
		boolean bold = false;
		if (busy) {
			upd = T.updating;
		} else if (fetched > 0) {
			Calendar c = Calendar.getInstance();
			c.setTimeInMillis(fetched);
			String when = Texts.clock(String.format("%02d:%02d", c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE)), clk12);
			upd = T.updated + " " + when;
			if (offline) {
				upd = "! " + T.noData + " " + when;
				bold = true;
			}
		}
		if (upd.length() > 0) {
			float up = fit(bold, 27, batLeft - 123 - 14, upd);
			ltext(bold, up, fb + 26, 123, upd, bold ? Gfx.BLACK : Gfx.GRAY5);
		}
	}
}
