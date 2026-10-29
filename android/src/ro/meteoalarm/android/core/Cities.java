package ro.meteoalarm.android.core;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** The towns of cities.txt ("county|town|lat|lon"), by county. */
public final class Cities {
	public static final class City {
		public final String county, name;
		public final double lat, lon;

		public City(String county, String name, double lat, double lon) {
			this.county = county;
			this.name = name;
			this.lat = lat;
			this.lon = lon;
		}

		/** "Călărași|Călărași|44.2058|27.3306", as kept in the settings. */
		public String key() { return county + "|" + name + "|" + lat + "|" + lon; }

		public static City fromKey(String k) {
			String[] p = k.split("\\|");
			if (p.length != 4) return null;
			return new City(p[0], p[1], Double.parseDouble(p[2]), Double.parseDouble(p[3]));
		}

		/** "Călărași, CL". */
		public String label() {
			String c = countyCode(county);
			return c.length() > 0 ? name + ", " + c : name;
		}
	}

	public final Map<String, List<City>> byCounty = new LinkedHashMap<String, List<City>>();

	public Cities(String text) {
		for (String line : text.split("\n")) {
			line = line.trim();
			if (line.length() == 0 || line.startsWith("#")) continue;
			String[] p = line.split("\\|");
			if (p.length != 4 || p[0].equals("*")) continue;
			try {
				City c = new City(p[0], p[1], Double.parseDouble(p[2]), Double.parseDouble(p[3]));
				List<City> l = byCounty.get(c.county);
				if (l == null) byCounty.put(c.county, l = new ArrayList<City>());
				l.add(c);
			} catch (NumberFormatException e) {
				// skip a bad line
			}
		}
	}

	public City find(String name) {
		for (List<City> l : byCounty.values()) for (City c : l) if (c.name.equals(name)) return c;
		return null;
	}

	/** Licence plate code of a Romanian county ("Călărași" -> "CL"). */
	public static String countyCode(String c) {
		String[] t = { "Alba", "AB", "Arad", "AR", "Argeș", "AG", "Bacău", "BC", "Bihor", "BH", "Bistrița-Năsăud", "BN",
				"Botoșani", "BT", "Brașov", "BV", "Brăila", "BR", "București", "B", "Buzău", "BZ", "Caraș-Severin", "CS",
				"Cluj", "CJ", "Constanța", "CT", "Covasna", "CV", "Călărași", "CL", "Dolj", "DJ", "Dâmbovița", "DB",
				"Galați", "GL", "Giurgiu", "GR", "Gorj", "GJ", "Harghita", "HR", "Hunedoara", "HD", "Ialomița", "IL",
				"Iași", "IS", "Ilfov", "IF", "Maramureș", "MM", "Mehedinți", "MH", "Mureș", "MS", "Neamț", "NT", "Olt",
				"OT", "Prahova", "PH", "Satu Mare", "SM", "Sibiu", "SB", "Suceava", "SV", "Sălaj", "SJ", "Teleorman",
				"TR", "Timiș", "TM", "Tulcea", "TL", "Vaslui", "VS", "Vrancea", "VN", "Vâlcea", "VL" };
		for (int k = 0; k < t.length; k += 2) if (t[k].equals(c)) return t[k + 1];
		return "";
	}
}
