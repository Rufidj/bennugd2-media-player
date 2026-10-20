package org.libsdl.app;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import java.util.HashMap;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;

/*
 *  Mando en pantalla: en un movil no hay ni mando ni teclado, asi que se dibuja
 *  una cruceta y dos botones (con el estilo de la consola) y los toques se
 *  convierten en teclas para el motor, que ya sabe moverse con ellas.
 *
 *  Las posiciones estan en el espacio logico del juego (1280x720) y se escalan
 *  al tamano de la vista, asi que el mando queda en el mismo sitio que en el
 *  resto de plataformas.
 */
public class TouchPadView extends View {

    public static final int BTN_UP = 0, BTN_DOWN = 1, BTN_LEFT = 2, BTN_RIGHT = 3,
                            BTN_OK = 4, BTN_BACK = 5, BTN_COUNT = 6;

    /* cruceta abajo a la izquierda, botones a la derecha (el reproductor no tiene nada ahi) */
    private static final float[] LOGICAL_X = { 1010, 1010,  962, 1058, 1180, 1200 };
    private static final float[] LOGICAL_Y = {  520,  616,  568,  568,  490,  610 };
    private static final float[] LOGICAL_R = {   27,   27,   27,   27,   38,  34 };

    private static final int[] KEYCODE = {
        KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN,
        KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT,
        KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_ESCAPE
    };

    private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint line = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final HashMap<Integer, Integer> fingers = new HashMap<Integer, Integer>();  /* id del dedo -> boton */
    private final boolean[] pressed = new boolean[BTN_COUNT];
    private final Runnable[] release = new Runnable[BTN_COUNT];

    public TouchPadView(Context context) {
        super(context);
        fill.setStyle(Paint.Style.FILL);
        line.setStyle(Paint.Style.STROKE);
        line.setStrokeCap(Paint.Cap.ROUND);
        setClickable(true);
    }

    /* --- dibujo ------------------------------------------------------------ */

    @Override
    protected void onDraw(Canvas canvas) {
        float sx = getWidth() / 1280f, sy = getHeight() / 720f;
        for (int i = 0; i < BTN_COUNT; i++) {
            float x = LOGICAL_X[i] * sx, y = LOGICAL_Y[i] * sy, r = LOGICAL_R[i] * sx;
            int a = pressed[i] ? 90 : 40;
            fill.setColor(0x40FFFFFF | (a << 24));
            canvas.drawCircle(x, y, r, fill);
            line.setColor(0xC0FFFFFF);
            line.setStrokeWidth(Math.max(2f, r * 0.10f));
            canvas.drawCircle(x, y, r, line);
            if (i == BTN_OK) {                    // la X
                float d = r * 0.45f;
                line.setColor(0xE0FFFFFF);
                line.setStrokeWidth(Math.max(3f, r * 0.16f));
                canvas.drawLine(x - d, y - d, x + d, y + d, line);
                canvas.drawLine(x - d, y + d, x + d, y - d, line);
            } else if (i == BTN_BACK) {           // la O
                float d = r * 0.45f;
                line.setColor(0xE0FFFFFF);
                line.setStrokeWidth(Math.max(3f, r * 0.16f));
                canvas.drawCircle(x, y, d, line);
            }
        }
    }

    /* --- entrada ------------------------------------------------------------ */

    private int buttonAt(float x, float y) {
        float sx = getWidth() / 1280f, sy = getHeight() / 720f;
        for (int i = 0; i < BTN_COUNT; i++) {
            float dx = x - LOGICAL_X[i] * sx, dy = y - LOGICAL_Y[i] * sy;
            float r = LOGICAL_R[i] * sx * 1.15f;   // un poco de margen
            if (dx * dx + dy * dy <= r * r) return i;
        }
        return -1;
    }

    private void press(int button, boolean down) {
        if (button < 0 || button >= BTN_COUNT) return;
        if (pressed[button] == down) return;
        pressed[button] = down;
        if (down) {
            if (release[button] != null) { removeCallbacks(release[button]); release[button] = null; }
            SDLActivity.onNativeKeyDown(KEYCODE[button]);
        } else {
            /* la soltura se manda en el fotograma siguiente: si el motor procesase
               la pulsacion y la soltura en el mismo frame, no llegaria a ver la
               tecla pulsada (y con ella, la orden de moverse) */
            final int b = button;
            Runnable r = new Runnable() {
                @Override
                public void run() {
                    release[b] = null;
                    SDLActivity.onNativeKeyUp(KEYCODE[b]);
                }
            };
            release[button] = r;
            postOnAnimation(r);
        }
        invalidate();
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        int action = event.getActionMasked();
        int index = event.getActionIndex();
        switch (action) {
            case MotionEvent.ACTION_DOWN:
            case MotionEvent.ACTION_POINTER_DOWN: {
                int button = buttonAt(event.getX(index), event.getY(index));
                if (button < 0) return false;      // este toque no es del mando
                fingers.put(Integer.valueOf(event.getPointerId(index)), Integer.valueOf(button));
                press(button, true);
                return true;
            }
            case MotionEvent.ACTION_MOVE: {
                boolean handled = false;
                for (int i = 0; i < event.getPointerCount(); i++) {
                    int id = event.getPointerId(i);
                    if (!fingers.containsKey(id)) continue;
                    int old = fingers.get(id).intValue();
                    int button = buttonAt(event.getX(i), event.getY(i));
                    if (button != old) {
                        press(old, false);
                        if (button >= 0) {
                            fingers.put(Integer.valueOf(id), Integer.valueOf(button));
                            press(button, true);
                        } else {
                            fingers.remove(Integer.valueOf(id));
                        }
                    }
                    handled = true;
                }
                return handled;
            }
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_POINTER_UP:
            case MotionEvent.ACTION_CANCEL: {
                Integer b = fingers.get(Integer.valueOf(event.getPointerId(index)));
                int button = (b == null) ? -1 : b.intValue();
                if (button < 0) return false;
                press(button, false);
                fingers.remove(Integer.valueOf(event.getPointerId(index)));
                return true;
            }
        }
        return false;
    }
}
