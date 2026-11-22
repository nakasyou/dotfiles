{ writers
, python3Packages
}:

# Holding Super grabs the TrackPoint but stays transparent: motion and
# buttons are forwarded to a virtual pointer. Pushing the stick while
# *additionally* holding the middle button switches to consume mode and
# emits Ctrl+Alt+arrow chords per flick direction; niri binds
# Mod+Ctrl+Alt+arrows to its tile-move actions. Middle-button presses are
# swallowed while Super is held so gestures never leak stray clicks.
# Arrows+Ctrl+Alt are used instead of F-keys because the jp xkb layout maps
# the F13-F16 keycodes to XF86 keysyms, and because the flick keys go through
# a dedicated keyboard-tagged uinput device (a pointer-classified device's
# key events never reach niri's keyboard handler).
writers.writePython3Bin "niri-trackpoint-move" {
  libraries = [ python3Packages.evdev ];
  doCheck = false;
} ''
  import os
  import selectors
  import time

  from evdev import InputDevice, UInput, ecodes, list_devices

  # Accumulated TrackPoint counts needed to trigger one tile move.
  THRESHOLD = int(os.environ.get("FLICK_THRESHOLD", "80"))
  # A pause longer than this resets the accumulators so slow pointer drift
  # never piles up into an accidental move.
  IDLE_RESET_SEC = float(os.environ.get("FLICK_IDLE_RESET_SEC", "0.25"))
  # Minimum time between two emitted moves; caps how fast a hard push can
  # march a window across tiles.
  FIRE_COOLDOWN_SEC = float(os.environ.get("FLICK_COOLDOWN_SEC", "0.18"))

  FLICK_MODS = (ecodes.KEY_LEFTCTRL, ecodes.KEY_LEFTALT)
  FLICK_KEYS = {
      "left": ecodes.KEY_LEFT,
      "right": ecodes.KEY_RIGHT,
      "up": ecodes.KEY_UP,
      "down": ecodes.KEY_DOWN,
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
          if dev.name.startswith("niri-trackpoint-move"):
              continue  # our own uinput devices
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
          if dev.name.startswith("niri-trackpoint-move"):
              continue  # our own uinput devices
          keys = dev.capabilities().get(ecodes.EV_KEY, ())
          if ecodes.KEY_LEFTMETA in keys and ecodes.KEY_A in keys:
              keyboards.append(dev)
      return keyboards


  def flick(ui, code):
      for mod in FLICK_MODS:
          ui.write(ecodes.EV_KEY, mod, 1)
      ui.write(ecodes.EV_KEY, code, 1)
      ui.write(ecodes.EV_KEY, code, 0)
      for mod in reversed(FLICK_MODS):
          ui.write(ecodes.EV_KEY, mod, 0)
      ui.syn()


  def main():
      trackpoint, keyboards = None, []
      while trackpoint is None or not keyboards:
          trackpoint = trackpoint or find_trackpoint()
          keyboards = keyboards or find_keyboards()
          if trackpoint is None or not keyboards:
              time.sleep(2)

      # The full key range makes input_id tag this device as a keyboard.
      ui_keys = UInput(
          events={ecodes.EV_KEY: list(range(1, 250))},
          name="niri-trackpoint-move-keys",
      )
      # "trackpoint" in the name gives this device ID_INPUT_POINTINGSTICK, so
      # forwarded motion gets the user's trackpoint accel config.
      ui_ptr = UInput(
          events={
              ecodes.EV_KEY: list(BUTTON_CODES),
              ecodes.EV_REL: [
                  ecodes.REL_X, ecodes.REL_Y, ecodes.REL_WHEEL, ecodes.REL_HWHEEL,
              ],
          },
          name="niri-trackpoint-move-buttons",
      )

      sel = selectors.DefaultSelector()
      sel.register(trackpoint, selectors.EVENT_READ, "trackpoint")
      for kb in keyboards:
          sel.register(kb, selectors.EVENT_READ, "keyboard")
      print(
          f"watching '{trackpoint.name}' plus {len(keyboards)} keyboard(s)",
          flush=True,
      )

      held_meta = 0
      grabbed = False
      middle_held = False
      virtual_held = set()
      acc_x = acc_y = 0
      last_motion = 0.0
      last_fire = 0.0

      def release_virtual_buttons():
          for code in virtual_held:
              ui_ptr.write(ecodes.EV_KEY, code, 0)
          if virtual_held:
              ui_ptr.syn()
              virtual_held.clear()

      while True:
          for key, _ in sel.select():
              try:
                  events = key.fileobj.read()
              except OSError:
                  # Device vanished; exit so systemd restarts and rescans.
                  release_virtual_buttons()
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
                      elif held_meta == 0 and grabbed:
                          release_virtual_buttons()
                          trackpoint.ungrab()
                          grabbed = False
                      continue

                  # Trackpoint event. The middle button is always consumed and
                  # only tracked; other buttons pass through while grabbed.
                  if ev.type == ecodes.EV_KEY and ev.code == ecodes.BTN_MIDDLE:
                      middle_held = ev.value != 0
                      if middle_held:
                          acc_x = acc_y = 0
                      continue
                  if not grabbed:
                      continue

                  if ev.type == ecodes.EV_REL and not middle_held:
                      ui_ptr.write(ecodes.EV_REL, ev.code, ev.value)
                      ui_ptr.syn()
                  elif ev.type == ecodes.EV_KEY and ev.code in BUTTON_CODES:
                      ui_ptr.write(ecodes.EV_KEY, ev.code, ev.value)
                      ui_ptr.syn()
                      if ev.value == 1:
                          virtual_held.add(ev.code)
                      elif ev.value == 0:
                          virtual_held.discard(ev.code)
                  elif ev.type == ecodes.EV_REL and ev.code in (ecodes.REL_WHEEL, ecodes.REL_HWHEEL):
                      ui_ptr.write(ecodes.EV_REL, ev.code, ev.value)
                      ui_ptr.syn()
                  elif ev.type == ecodes.EV_REL and ev.code in (ecodes.REL_X, ecodes.REL_Y):
                      # consume mode: middle button held
                      if ev.timestamp() - last_motion > IDLE_RESET_SEC:
                          acc_x = acc_y = 0
                      last_motion = ev.timestamp()
                      if ev.code == ecodes.REL_X:
                          acc_x += ev.value
                      else:
                          acc_y += ev.value
                      if (
                          max(abs(acc_x), abs(acc_y)) >= THRESHOLD
                          and ev.timestamp() - last_fire >= FIRE_COOLDOWN_SEC
                      ):
                          if abs(acc_x) >= abs(acc_y):
                              flick(ui_keys, FLICK_KEYS["right" if acc_x > 0 else "left"])
                          else:
                              flick(ui_keys, FLICK_KEYS["down" if acc_y > 0 else "up"])
                          acc_x = acc_y = 0
                          last_fire = ev.timestamp()


  if __name__ == "__main__":
      main()
''
