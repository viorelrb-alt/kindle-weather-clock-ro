package ro.meteoalarm.android;

import android.content.Context;
import android.graphics.Canvas;
import android.view.MotionEvent;
import android.view.View;

import ro.meteoalarm.android.core.Screen;

/** Draws the Screen scaled to the phone: full width, the extra height going to the current weather. */
final class WeatherView extends View {
	interface Taps {
		void onMenu();

		void onRefresh();

		void onCity();
	}

	final Screen screen = new Screen();
	private final AndroidGfx gfx;
	private Taps taps;
	private float scale = 1, ox;

	WeatherView(Context ctx, Taps taps) {
		super(ctx);
		this.taps = taps;
		gfx = new AndroidGfx(ctx.getAssets());
		setBackgroundColor(0xFFFFFFFF);
	}

	@Override
	protected void onDraw(Canvas c) {
		int w = getWidth(), h = getHeight();
		if (w == 0 || h == 0) return;
		scale = w / Screen.W;
		float ch = h / scale;
		if (ch < Screen.BASE_H) {
			scale = h / Screen.BASE_H;
			ch = Screen.BASE_H;
		}
		ox = (w - Screen.W * scale) / 2;
		c.drawColor(screen.dark ? 0xFF262624 : 0xFFFFFFFF);
		c.save();
		c.translate(ox, 0);
		c.scale(scale, scale);
		gfx.c = c;
		screen.draw(gfx, ch);
		c.restore();
	}

	private static boolean in(float[] b, float x, float y) {
		return x >= b[0] - 12 && x <= b[0] + b[2] + 12 && y >= b[1] - 12 && y <= b[1] + b[3] + 12;
	}

	@Override
	public boolean onTouchEvent(MotionEvent e) {
		if (e.getAction() != MotionEvent.ACTION_UP) return true;
		float x = (e.getX() - ox) / scale, y = e.getY() / scale;
		if (in(screen.btnMenu, x, y)) taps.onMenu();
		else if (in(screen.btnRefresh, x, y)) taps.onRefresh();
		else if (in(screen.btnCity, x, y) || (y >= screen.cityTop && y <= screen.cityBottom && x < 420)) taps.onCity();
		return true;
	}
}
