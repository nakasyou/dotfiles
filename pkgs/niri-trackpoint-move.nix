{ writers
, python3Packages
}:

# Pushing the TrackPoint while holding Super grabs the stick and emits F13-F16
# per flick direction; niri binds those to its tile-move actions. The cursor
# stays put while grabbed and TrackPoint buttons are forwarded to a virtual
# pointer so Mod+click still works.
writers.writePython3Bin "niri-trackpoint-move" {
  libraries = [ python3Packages.evdev ];
  doCheck = false;
} ''
  import os
  import selectors
  import time

  from evdev import InputDevice, UInput, ecodes, list_devices

  # Accumulated TrackPoint counts needed to trigger one tile move.
  THRESHOLD = int(os.environ.get("FLICK_THRESHOLD", "60"))
  # A pause longer than this resets the accumulators so slow pointer drift
  # never piles up into an accidental move.
  IDLE_RESET_SEC = float(os.environ.get("FLICK_IDLE_RESET_SEC", "0.25"))

  FLICK_KEYS = {
      "left": ecodes.KEY_F13,
      "right": ecodes.KEY_F14,
      "up": ecodes.KEY_F15,
      "down": ecodes.KEY_F16,
  }
  META_CODES = (ecodes.KEY_LEFTMETA, ecodes.KEY_RIGHTMETA)
  BUTTON_CODES = (
      ecodes.BTN_LEFT,
      ecodes.BTN_MIDDLE,
      ecodes.BTN_RIGHT,
      ecodes.BTN_SIDE,
      ecodes.BTN_EXTRA,
      ecodes.BTN_FORWARD,
      ecodes.BTN_BACK,
  )


  def find_trackpoint():
      for path in list_devices():
          try:
              dev = InputDevice(path)
          except OSError:
              continue
          rel = dev.capabilities().get(ecodes.EV_REL, ())
          if "trackpoint" in dev.name.lower() and ecodes.REL_X in rel and ecodes.REL_Y in rel:
              return dev
      return None


  def find_keyboards():
      keyboards = []
      for path in list_devices():
          try:
              dev = InputDevice(path)
          except OSError:
              continue
          keys = dev.capabilities().get(ecodes.EV_KEY, ())
          if ecodes.KEY_LEFTMETA in keys and ecodes.KEY_A in keys:
              keyboards.append(dev)
      return keyboards


  def tap(ui, code):
      ui.write(ecodes.EV_KEY, code, 1)
      ui.write(ecodes.EV_KEY, code, 0)
      ui.syn()


  def main():
      trackpoint, keyboards = None, []
      while trackpoint is None or not keyboards:
          trackpoint = trackpoint or find_trackpoint()
          keyboards = keyboards or find_keyboards()
          if trackpoint is None or not keyboards:
              time.sleep(2)

      ui = UInput(
          events={
              ecodes.EV_KEY: list(FLICK_KEYS.values()) + list(BUTTON_CODES),
              ecodes.EV_REL: [ecodes.REL_X, ecodes.REL_Y],
          },
          name="niri-trackpoint-move",
      )

      sel = selectors.DefaultSelector()
      sel.register(trackpoint, selectors.EVENT_READ, "trackpoint")
      for kb in keyboards:
          sel.register(kb, selectors.EVENT_READ, "keyboard")

      held_meta = 0
      grabbed = False
      acc_x = acc_y = 0
      last_motion = 0.0

      while True:
          for key, _ in sel.select():
              try:
                  events = key.fileobj.read()
              except OSError:
                  # Device vanished; exit so systemd restarts and rescans.
                  return
              for ev in events:
                  if key.data == "keyboard":
                      if ev.type != ecodes.EV_KEY or ev.code not in META_CODES:
                          continue
                      if ev.value == 1:
                          held_meta += 1
                      elif ev.value == 0 and held_meta > 0:
                          held_meta -= 1
                      if held_meta > 0 and not grabbed:
                          trackpoint.grab()
                          grabbed = True
                          acc_x = acc_y = 0
                      elif held_meta == 0 and grabbed:
                          trackpoint.ungrab()
                          grabbed = False
                  elif grabbed:
                      if ev.type == ecodes.EV_KEY and ev.code in BUTTON_CODES:
                          ui.write(ecodes.EV_KEY, ev.code, ev.value)
                          ui.syn()
                      elif ev.type == ecodes.EV_REL and ev.code in (ecodes.REL_X, ecodes.REL_Y):
                          if ev.timestamp() - last_motion > IDLE_RESET_SEC:
                              acc_x = acc_y = 0
                          last_motion = ev.timestamp()
                          if ev.code == ecodes.REL_X:
                              acc_x += ev.value
                          else:
                              acc_y += ev.value
                          if abs(acc_x) >= THRESHOLD or abs(acc_y) >= THRESHOLD:
                              if abs(acc_x) >= abs(acc_y):
                                  tap(ui, FLICK_KEYS["right" if acc_x > 0 else "left"])
                              else:
                                  tap(ui, FLICK_KEYS["down" if acc_y > 0 else "up"])
                              acc_x = acc_y = 0


  if __name__ == "__main__":
      main()
'';
