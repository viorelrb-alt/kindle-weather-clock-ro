package ro.meteoalarm.android;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.os.BatteryManager;
import android.os.Bundle;
import android.os.Handler;
import android.view.View;
import android.view.WindowManager;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.List;
import java.util.TimeZone;

import ro.meteoalarm.android.core.Cities;
import ro.meteoalarm.android.core.Screen;
import ro.meteoalarm.android.core.Texts;
import ro.meteoalarm.android.core.Warnings;
import ro.meteoalarm.android.core.Weather;

/**
 * Meteo Alarm Android: the Kindle weather clock on a phone. The weather is fetched every 15 minutes
 * while the app is open (every hour at night) and kept on disk, so it opens at once offline.
 */
public final class MainActivity extends Activity implements WeatherView.Taps {
	static final String VERSION = "Meteo Alarm Android v0.1";
	private static final long WEATHER_MS = 15 * 60000L, NIGHT_MS = 60 * 60000L;

	private WeatherView view;
	private Screen s;
	private Cities cities;
	private SharedPreferences prefs;
	private final Handler handler = new Handler();
	private boolean fetching;
	private long lastTry;

	private final Runnable tick = new Runnable() {
		public void run() {
			s.now = Calendar.getInstance();
			s.offline = s.fetched > 0 && System.currentTimeMillis() - s.fetched > 2 * interval() + 5 * 60000L;
			long iv = s.w == null ? 60000L : interval();
			if (System.currentTimeMillis() - Math.max(s.fetched, lastTry) >= iv) fetch();
			view.invalidate();
			// Next tick at the start of the next minute, for the clock.
			handler.postDelayed(this, 60000 - System.currentTimeMillis() % 60000 + 50);
		}
	};

	private final BroadcastReceiver battery = new BroadcastReceiver() {
		public void onReceive(Context ctx, Intent i) {
			int lvl = i.getIntExtra(BatteryManager.EXTRA_LEVEL, -1), sc = i.getIntExtra(BatteryManager.EXTRA_SCALE, 100);
			s.batt = lvl < 0 ? -1 : lvl * 100 / Math.max(1, sc);
			s.charging = i.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0;
			view.invalidate();
		}
	};

	@Override
	protected void onCreate(Bundle b) {
		super.onCreate(b);
		prefs = getSharedPreferences("settings", MODE_PRIVATE);
		view = new WeatherView(this, this);
		s = view.screen;
		try {
			cities = new Cities(readAll(getAssets().open("cities.txt")));
		} catch (Exception e) {
			cities = new Cities("");
		}
		applySettings();
		loadCache();
		setContentView(view);
	}

	private long interval() {
		int h = Calendar.getInstance().get(Calendar.HOUR_OF_DAY);
		return h >= 23 || h < 6 ? NIGHT_MS : WEATHER_MS;
	}

	private void applySettings() {
		s.T = new Texts("en".equals(prefs.getString("lang", "ro")));
		s.unitF = prefs.getBoolean("unitF", false);
		s.clk12 = prefs.getBoolean("clk12", false);
		Cities.City c = Cities.City.fromKey(prefs.getString("city", ""));
		if (c == null) c = cities.find("Călărași");
		if (c == null) c = new Cities.City("Călărași", "Călărași", 44.2058, 27.3306);
		s.city = c;
		if (prefs.getBoolean("keepOn", true)) getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
		else getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
	}

	@Override
	protected void onResume() {
		super.onResume();
		hideBars();
		registerReceiver(battery, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
		handler.removeCallbacks(tick);
		handler.post(tick);
	}

	@Override
	protected void onPause() {
		super.onPause();
		handler.removeCallbacks(tick);
		try {
			unregisterReceiver(battery);
		} catch (Exception e) {
			// not registered
		}
	}

	@Override
	public void onWindowFocusChanged(boolean focus) {
		super.onWindowFocusChanged(focus);
		if (focus) hideBars();
	}

	/** Full screen like the Kindle: status and navigation bars hidden until a swipe from the edge. */
	private void hideBars() {
		view.setSystemUiVisibility(View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY | View.SYSTEM_UI_FLAG_FULLSCREEN
				| View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
				| View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN);
	}

	// --- Data --------------------------------------------------------------------------

	private static String readAll(InputStream in) throws Exception {
		ByteArrayOutputStream out = new ByteArrayOutputStream();
		byte[] buf = new byte[16384];
		int n;
		while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
		in.close();
		return new String(out.toByteArray(), "UTF-8");
	}

	private String readCache(String name) {
		try {
			return readAll(new FileInputStream(new File(getFilesDir(), name)));
		} catch (Exception e) {
			return null;
		}
	}

	private void writeCache(String name, String text) {
		try {
			FileOutputStream out = new FileOutputStream(new File(getFilesDir(), name));
			out.write(text.getBytes("UTF-8"));
			out.close();
		} catch (Exception e) {
			// the cache is only a convenience
		}
	}

	/** The last download, if it was for the chosen town. */
	private void loadCache() {
		if (!s.city.key().equals(prefs.getString("cacheCity", ""))) return;
		try {
			String f = readCache("forecast.json");
			if (f != null) s.w = Weather.parse(f);
			s.fetched = prefs.getLong("fetched", 0);
			String p = readCache("pollen.json");
			if (p != null) {
				Object[] r = Weather.parsePollen(p);
				s.pollenLvl = (Integer) r[0];
				s.pollenPlant = (String) r[1];
			}
			String x = readCache("warn.xml");
			if (x != null) s.warns = Warnings.parse(x, s.city.county, System.currentTimeMillis());
		} catch (Exception e) {
			s.w = null;
		}
	}

	private void fetch() {
		if (fetching) return;
		fetching = true;
		lastTry = System.currentTimeMillis();
		s.busy = true;
		view.invalidate();
		final Cities.City c = s.city;
		new Thread(new Runnable() {
			public void run() {
				String f = null, p = null, x = null;
				try {
					f = Weather.get(Weather.forecastUrl(c.lat, c.lon, TimeZone.getDefault().getID()));
					Weather.parse(f);
				} catch (Exception e) {
					f = null;
				}
				try {
					p = Weather.get(Weather.pollenUrl(c.lat, c.lon));
				} catch (Exception e) {
					p = null;
				}
				try {
					x = Weather.get(Warnings.FEED);
				} catch (Exception e) {
					x = null;
				}
				final String ff = f, pp = p, xx = x;
				handler.post(new Runnable() {
					public void run() {
						done(c, ff, pp, xx);
					}
				});
			}
		}).start();
	}

	private void done(Cities.City c, String f, String p, String x) {
		fetching = false;
		s.busy = false;
		if (c != s.city) { // the town changed meanwhile
			fetch();
			return;
		}
		long now = System.currentTimeMillis();
		if (f != null) {
			s.w = Weather.parse(f);
			s.fetched = now;
			s.offline = false;
			writeCache("forecast.json", f);
			prefs.edit().putLong("fetched", now).putString("cacheCity", c.key()).apply();
		} else if (s.w == null) {
			s.error = s.T.en ? "No internet connection" : "Fără conexiune la internet";
		}
		if (p != null) {
			try {
				Object[] r = Weather.parsePollen(p);
				s.pollenLvl = (Integer) r[0];
				s.pollenPlant = (String) r[1];
				writeCache("pollen.json", p);
			} catch (Exception e) {
				// keep the last pollen
			}
		}
		if (x != null) {
			s.warns = Warnings.parse(x, c.county, now);
			writeCache("warn.xml", x);
		}
		view.invalidate();
	}

	// --- Taps --------------------------------------------------------------------------

	private AlertDialog.Builder dialog() {
		return new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Light_Dialog_Alert);
	}

	private void show(AlertDialog.Builder b) {
		AlertDialog d = b.create();
		d.setOnDismissListener(new DialogInterface.OnDismissListener() {
			public void onDismiss(DialogInterface di) {
				hideBars();
			}
		});
		d.show();
	}

	public void onRefresh() {
		fetch();
	}

	public void onMenu() {
		final boolean en = s.T.en;
		boolean keepOn = prefs.getBoolean("keepOn", true);
		String[] items = en
				? new String[] { "Refresh now", "Choose town", s.unitF ? "Show °C" : "Show °F", s.clk12 ? "24-hour clock" : "12-hour clock",
						"Limba română", keepOn ? "Let the screen sleep" : "Keep the screen on", "About" }
				: new String[] { "Actualizează acum", "Alege localitatea", s.unitF ? "Afișează °C" : "Afișează °F",
						s.clk12 ? "Ceas 24 de ore" : "Ceas 12 ore (AM/PM)", "English", keepOn ? "Lasă ecranul să se stingă" : "Ține ecranul aprins",
						"Despre" };
		show(dialog().setTitle("☰").setItems(items, new DialogInterface.OnClickListener() {
			public void onClick(DialogInterface d, int k) {
				SharedPreferences.Editor e = prefs.edit();
				switch (k) {
				case 0: fetch(); return;
				case 1: onCity(); return;
				case 2: e.putBoolean("unitF", !s.unitF); break;
				case 3: e.putBoolean("clk12", !s.clk12); break;
				case 4: e.putString("lang", en ? "ro" : "en"); break;
				case 5: e.putBoolean("keepOn", !prefs.getBoolean("keepOn", true)); break;
				default: about(); return;
				}
				e.apply();
				applySettings();
				view.invalidate();
			}
		}));
	}

	private void about() {
		String msg = s.T.en
				? "Test version for phones, ported from Meteo Alarm Kindle v2.061.\n\nWeather: Open-Meteo (DWD ICON). Warnings: MeteoAlarm (ANM). Font: Liberation Sans."
				: "Versiune de test pentru telefon, portată din Meteo Alarm Kindle v2.061.\n\nVremea: Open-Meteo (DWD ICON). Avertizări: MeteoAlarm (ANM). Font: Liberation Sans.";
		show(dialog().setTitle(VERSION).setMessage(msg).setPositiveButton("OK", null));
	}

	/** Favourites (the last three towns) and the county list. */
	public void onCity() {
		final List<Cities.City> favs = new ArrayList<Cities.City>();
		for (String k : prefs.getString("favs", "").split("\n")) {
			Cities.City c = Cities.City.fromKey(k);
			if (c != null) favs.add(c);
		}
		final boolean en = s.T.en;
		if (favs.isEmpty()) {
			pickCounty();
			return;
		}
		String[] items = new String[favs.size() + 1];
		for (int k = 0; k < favs.size(); k++) items[k] = favs.get(k).label();
		items[favs.size()] = en ? "Choose county…" : "Alege județul…";
		show(dialog().setTitle(en ? "Town" : "Localitatea").setItems(items, new DialogInterface.OnClickListener() {
			public void onClick(DialogInterface d, int k) {
				if (k < favs.size()) choose(favs.get(k));
				else pickCounty();
			}
		}));
	}

	private void pickCounty() {
		final String[] counties = cities.byCounty.keySet().toArray(new String[0]);
		show(dialog().setTitle(s.T.en ? "Choose county" : "Alege județul").setItems(counties, new DialogInterface.OnClickListener() {
			public void onClick(DialogInterface d, int k) {
				pickTown(counties[k]);
			}
		}));
	}

	private void pickTown(String county) {
		final List<Cities.City> l = cities.byCounty.get(county);
		String[] items = new String[l.size()];
		for (int k = 0; k < l.size(); k++) items[k] = l.get(k).name;
		show(dialog().setTitle(county).setItems(items, new DialogInterface.OnClickListener() {
			public void onClick(DialogInterface d, int k) {
				choose(l.get(k));
			}
		}));
	}

	private void choose(Cities.City c) {
		StringBuilder favs = new StringBuilder(c.key());
		int n = 1;
		for (String k : prefs.getString("favs", "").split("\n")) {
			if (n >= 3 || k.length() == 0 || k.equals(c.key())) continue;
			favs.append('\n').append(k);
			n++;
		}
		prefs.edit().putString("city", c.key()).putString("favs", favs.toString()).apply();
		s.city = c;
		s.w = null;
		s.warns = null;
		s.pollenLvl = -1;
		s.fetched = 0;
		s.error = "";
		view.invalidate();
		fetch();
	}
}
