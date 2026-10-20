package org.libsdl.app;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;

/*
 *  Toques en pantalla. En un movil no hay mando ni teclado, asi que los dedos
 *  se convierten en lo que el reproductor ya entiende (teclas):
 *
 *    - un toque: "aceptar" (en el explorador abre lo que haya debajo)
 *    - un deslizamiento: "mover" (vertical arriba/abajo, horizontal izquierda/derecha)
 *    - una pulsacion larga: "opciones"
 *
 *  Los toques tambien se pasan al motor (asi el reproductor sabe en que punto
 *  de la pantalla se ha tocado, y puede abrir la fila que haya ahi).
 *  El boton de atras del sistema lo pone la actividad como "atras".
 */
public class TouchOverlayView extends View {

    private static final int MAX_POINTERS = 10;
    private static final float SWIPE_STEP = 55f;   // pixeles de vista por paso
    private static final float TAP_SLOP = 24f;      // movimiento maximo para que sea un toque
    private static final long TAP_TIME = 400;       // ms: mas que esto es una pulsacion larga

    private final Paint dot = new Paint(Paint.ANTI_ALIAS_FLAG);

    private final int[] ids = new int[MAX_POINTERS];
    private final float[] px = new float[MAX_POINTERS];
    private final float[] py = new float[MAX_POINTERS];
    private final float[] sx = new float[MAX_POINTERS];
    private final float[] sy = new float[MAX_POINTERS];
    private final float[] accX = new float[MAX_POINTERS];
    private final float[] accY = new float[MAX_POINTERS];
    private final long[] time = new long[MAX_POINTERS];
    private final boolean[] used = new boolean[MAX_POINTERS];

    public TouchOverlayView(Context context) {
        super(context);
        dot.setColor(0x60FFFFFF);
        setClickable(true);
    }

    /* --- dibujo: un puntito donde se esta tocando ------------------------------ */

    @Override
    protected void onDraw(Canvas canvas) {
        for (int i = 0; i < MAX_POINTERS; i++) {
            if (!used[i]) continue;
            canvas.drawCircle(px[i], py[i], 26f, dot);
        }
    }

    /* --- entrada --------------------------------------------------------------- */

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        int action = event.getActionMasked();
        int index = event.getActionIndex();
        switch (action) {
            case MotionEvent.ACTION_DOWN:
            case MotionEvent.ACTION_POINTER_DOWN: {
                int slot = freeSlot();
                if (slot < 0) return true;
                ids[slot] = event.getPointerId(index);
                px[slot] = sx[slot] = event.getX(index);
                py[slot] = sy[slot] = event.getY(index);
                accX[slot] = accY[slot] = 0;
                time[slot] = event.getEventTime();
                used[slot] = true;
                forward(event, index, action);
                invalidate();
                return true;
            }
            case MotionEvent.ACTION_MOVE: {
                for (int i = 0; i < MAX_POINTERS; i++) {
                    if (!used[i]) continue;
                    int k = event.findPointerIndex(ids[i]);
                    if (k < 0) continue;
                    float x = event.getX(k), y = event.getY(k);
                    accX[i] += x - px[i];
                    accY[i] += y - py[i];
                    px[i] = x; py[i] = y;
                    // un deslizamientovertical mueve la lista; el horizontal, los menus
                    while (Math.abs(accY[i]) >= SWIPE_STEP) {
                        sendKey(accY[i] > 0 ? KeyEvent.KEYCODE_DPAD_DOWN : KeyEvent.KEYCODE_DPAD_UP);
                        accY[i] -= (accY[i] > 0 ? SWIPE_STEP : -SWIPE_STEP);
                    }
                    while (Math.abs(accX[i]) >= SWIPE_STEP) {
                        sendKey(accX[i] > 0 ? KeyEvent.KEYCODE_DPAD_RIGHT : KeyEvent.KEYCODE_DPAD_LEFT);
                        accX[i] -= (accX[i] > 0 ? SWIPE_STEP : -SWIPE_STEP);
                    }
                }
                forwardAll(event);
                invalidate();
                return true;
            }
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_POINTER_UP: {
                int slot = slotOf(event.getPointerId(index));
                if (slot >= 0) {
                    float dx = px[slot] - sx[slot], dy = py[slot] - sy[slot];
                    long dt = event.getEventTime() - time[slot];
                    if (dx * dx + dy * dy <= TAP_SLOP * TAP_SLOP) {
                        // un toque: "aceptar"; si se mantiene mucho: "opciones"
                        if (dt <= TAP_TIME) sendKey(KeyEvent.KEYCODE_ENTER);
                        else sendKey(KeyEvent.KEYCODE_M);
                    }
                    used[slot] = false;
                }
                forward(event, index, action);
                invalidate();
                return true;
            }
            case MotionEvent.ACTION_CANCEL: {
                for (int i = 0; i < MAX_POINTERS; i++) used[i] = false;
                invalidate();
                return true;
            }
        }
        return false;
    }

    /* --- pasar los toques al motor --------------------------------------------- */

    private void forward(MotionEvent event, int index, int action) {
        int devId = event.getDeviceId();
        if (devId < 0) devId -= 1;
        int pid = event.getPointerId(index);
        float x = getWidth() > 0 ? event.getX(index) / getWidth() : 0;
        float y = getHeight() > 0 ? event.getY(index) / getHeight() : 0;
        float p = event.getPressure(index);
        if (p > 1.0f) p = 1.0f;
        SDLActivity.onNativeTouch(devId, pid, action, x, y, p);
    }

    private void forwardAll(MotionEvent event) {
        for (int i = 0; i < event.getPointerCount(); i++) {
            forward(event, i, MotionEvent.ACTION_MOVE);
        }
    }

    /* --- teclas ---------------------------------------------------------------- */

    /* La tecla se suelta en el fotograma siguiente: si el motor procesase la
       pulsacion y la soltura en el mismo frame, no llegaria a ver la tecla. */
    private void sendKey(final int keycode) {
        SDLActivity.onNativeKeyDown(keycode);
        postOnAnimation(new Runnable() {
            @Override
            public void run() {
                SDLActivity.onNativeKeyUp(keycode);
            }
        });
    }

    private int freeSlot() {
        for (int i = 0; i < MAX_POINTERS; i++) if (!used[i]) return i;
        return -1;
    }

    private int slotOf(int id) {
        for (int i = 0; i < MAX_POINTERS; i++) if (used[i] && ids[i] == id) return i;
        return -1;
    }
}
