/// <reference path="./@girs/index.d.ts" />
import { Variable, execAsync } from 'astal'
import app from 'astal/gtk4/app'
import { Astal, Gtk, type Gdk } from 'astal/gtk4'
import AstalNotifd from 'gi://AstalNotifd?version=0.1'
import AstalTray from 'gi://AstalTray?version=0.1'
import GObject from 'gi://GObject'
import GLib from 'gi://GLib'
import Gio from 'gi://Gio'
import GioUnix from 'gi://GioUnix?version=2.0'
import System from 'system'
import style from './style.css'
import { animateMaterialSpring, expressiveMotion } from './material-motion'

const controlCenterToggles = new Map<number, () => void>()
let gcSource = 0

function scheduleGarbageCollection() {
  if (gcSource !== 0) return
  gcSource = GLib.idle_add(GLib.PRIORITY_LOW, () => {
    gcSource = 0
    System.gc()
    return GLib.SOURCE_REMOVE
  })
}

type NotificationSnapshot = {
  id: number
  appName: string
  appIcon: string
  appIconFile: string
  summary: string
  body: string
  time: number
  actions: Array<{ id: string; label: string }>
}

type SystemState = {
  volume: number
  muted: boolean
  network: 'wifi' | 'ethernet' | 'offline'
  batteryIcon: string
  batteryVisible: boolean
  brightness: number
  wifiEnabled: boolean
  bluetoothEnabled: boolean
  darkMode: boolean
  nightMode: boolean
  powerProfile: string
}

function notificationIcon(notification: any) {
  const supplied = String(notification.appIcon || '')
  if (supplied.startsWith('file://')) {
    return { appIcon: '', appIconFile: GLib.filename_from_uri(supplied)[0] }
  }
  if (supplied.startsWith('/')) {
    return { appIcon: '', appIconFile: supplied }
  }
  if (supplied) return { appIcon: supplied, appIconFile: '' }

  const desktopEntry = String(notification.desktopEntry || '')
  const desktopIds = desktopEntry
    ? [desktopEntry, desktopEntry.endsWith('.desktop') ? '' : `${desktopEntry}.desktop`]
    : []
  for (const desktopId of desktopIds) {
    if (!desktopId) continue
    const info = GioUnix.DesktopAppInfo.new(desktopId)
    const icon = info?.get_icon()
    if (icon instanceof Gio.FileIcon) {
      return { appIcon: '', appIconFile: icon.get_file().get_path() || '' }
    }
    if (icon instanceof Gio.ThemedIcon) {
      const name = icon.get_names()[0]
      if (name) return { appIcon: name, appIconFile: '' }
    }
  }
  return { appIcon: 'dialog-information-symbolic', appIconFile: '' }
}

function clearBox(box: Gtk.Box) {
  let child = box.get_first_child()
  while (child) {
    const next = child.get_next_sibling()
    box.remove(child)
    // Removing a GTK widget only unparents it. Explicitly dispose the detached
    // tree so GJS signal closures (notification actions, dismiss handlers,
    // labels and images) cannot retain every previous history render.
    child.run_dispose()
    child = next
  }
}

function notificationCard(
  snapshot: NotificationSnapshot,
  notification: any,
  compact = false,
) {
  const card = new Astal.Box({
    cssClasses: ['notification-card', compact ? 'compact' : 'popup'],
    orientation: Gtk.Orientation.VERTICAL,
    spacing: 10,
    widthRequest: compact ? 300 : 360,
    hexpand: false,
  })
  const header = new Astal.Box({
    cssClasses: ['notification-header'],
    spacing: 10,
  })
  const appIcon = new Gtk.Image({
    cssClasses: ['notification-app-icon'],
    pixelSize: compact ? 28 : 34,
  })
  if (snapshot.appIconFile) appIcon.file = snapshot.appIconFile
  else appIcon.iconName = snapshot.appIcon
  header.append(appIcon)
  header.append(new Gtk.Label({
    cssClasses: ['notification-app-name'],
    label: snapshot.appName || 'Notification',
    xalign: 0,
    hexpand: true,
    ellipsize: 3,
  }))
  const age = Math.max(0, Math.floor(Date.now() / 1000 - snapshot.time))
  header.append(new Gtk.Label({
    cssClasses: ['notification-time'],
    label: age < 60 ? 'たった今' : `${Math.floor(age / 60)}分前`,
  }))
  card.append(header)

  if (snapshot.summary) {
    card.append(new Gtk.Label({
      cssClasses: ['notification-summary'],
      label: snapshot.summary,
      xalign: 0,
      ellipsize: 3,
      lines: 1,
      maxWidthChars: compact ? 34 : 42,
    }))
  }
  if (snapshot.body) {
    card.append(new Gtk.Label({
      cssClasses: ['notification-body'],
      label: snapshot.body,
      xalign: 0,
      wrap: true,
      wrapMode: 2,
      ellipsize: 3,
      lines: compact ? 2 : 3,
      maxWidthChars: compact ? 34 : 42,
      useMarkup: false,
    }))
  }

  if (!compact) {
    const actions = new Astal.Box({
      cssClasses: ['notification-actions'],
      spacing: 8,
      halign: Gtk.Align.END,
    })
    const dismiss = new Gtk.Button({
      cssClasses: ['notification-action', 'dismiss'],
      label: '閉じる',
    })
    dismiss.connect('clicked', () => notification?.dismiss())
    actions.append(dismiss)
    for (const action of snapshot.actions.slice(0, 2)) {
      const button = new Gtk.Button({
        cssClasses: ['notification-action', 'primary'],
        label: action.label,
      })
      button.connect('clicked', () => notification?.invoke(action.id))
      actions.append(button)
    }
    card.append(actions)
  }
  return card
}

function NotificationUI(gdkmonitor: Gdk.Monitor, index: number) {
  const notifd = AstalNotifd.get_default()
  notifd.defaultTimeout = 6000
  const popupList = new Astal.Box({
    cssClasses: ['notification-popup-list'],
    orientation: Gtk.Orientation.VERTICAL,
    spacing: 12,
    widthRequest: 380,
    hexpand: false,
  })
  const historyList = new Astal.Box({
    cssClasses: ['notification-history-list'],
    orientation: Gtk.Orientation.VERTICAL,
    spacing: 10,
  })
  const history = new Map<number, NotificationSnapshot>()
  let popupWindow: Astal.Window | undefined
  let historyWidget: Astal.Box | undefined
  let stopPopupSpatialAnimation: (() => void) | undefined
  let stopPopupEffectsAnimation: (() => void) | undefined
  let popupAnimationToken = 0

  const animationsEnabled = () =>
    Gtk.Settings.get_default()?.gtkEnableAnimations !== false
  const stopPopupAnimations = () => {
    stopPopupSpatialAnimation?.()
    stopPopupEffectsAnimation?.()
    stopPopupSpatialAnimation = undefined
    stopPopupEffectsAnimation = undefined
  }

  const setPopupVisible = (visible: boolean) => {
    if (!popupWindow) return

    stopPopupAnimations()
    const token = ++popupAnimationToken
    if (!animationsEnabled()) {
      popupWindow.marginRight = 12
      popupList.opacity = 1
      popupWindow.visible = visible
      if (!visible) clearBox(popupList)
      return
    }

    if (visible) {
      // Updating an already-open stack (for example after dismissing one of
      // several notifications) should not replay the entrance motion for all
      // remaining cards.
      if (popupWindow.visible) {
        popupWindow.marginRight = 12
        popupList.opacity = 1
        return
      }

      popupWindow.marginRight = -16
      popupList.opacity = 0
      popupWindow.visible = true
      stopPopupSpatialAnimation = animateMaterialSpring(
        expressiveMotion.defaultSpatial,
        (progress) => {
          popupWindow!.marginRight = Math.round(-16 + 28 * progress)
        },
      )
      stopPopupEffectsAnimation = animateMaterialSpring(
        expressiveMotion.defaultEffects,
        (progress) => {
          popupList.opacity = Math.min(1, Math.max(0, progress))
        },
      )
      return
    }

    if (!popupWindow.visible) {
      clearBox(popupList)
      return
    }

    const startMargin = popupWindow.marginRight
    const startOpacity = popupList.opacity
    stopPopupSpatialAnimation = animateMaterialSpring(
      expressiveMotion.fastSpatial,
      (progress) => {
        popupWindow!.marginRight = Math.round(
          startMargin + (-16 - startMargin) * progress,
        )
      },
    )
    stopPopupEffectsAnimation = animateMaterialSpring(
      expressiveMotion.fastEffects,
      (progress) => {
        popupList.opacity = Math.max(0, startOpacity * (1 - progress))
      },
      () => {
        if (!popupWindow || popupAnimationToken !== token) return
        popupWindow.visible = false
        popupWindow.marginRight = 12
        popupList.opacity = 1
        clearBox(popupList)
      },
    )
  }

  const snapshot = (notification: any): NotificationSnapshot => {
    const icon = notificationIcon(notification)
    return {
      id: notification.id,
      appName: notification.appName,
      appIcon: icon.appIcon,
      appIconFile: icon.appIconFile,
      summary: notification.summary,
      body: notification.body,
      time: Number(notification.time) || Math.floor(Date.now() / 1000),
      actions: [...(notification.actions ?? [])].map((action: any) => ({
        id: action.id,
        label: action.label,
      })),
    }
  }
  const renderHistory = () => {
    clearBox(historyList)
    for (const item of [...history.values()].reverse().slice(0, 12)) {
      historyList.append(notificationCard(item, notifd.get_notification(item.id), true))
    }
    if (history.size === 0) {
      if (historyWidget) historyWidget.visible = false
      return
    }
    if (historyWidget) historyWidget.visible = true
  }
  const renderPopups = () => {
    const notifications = notifd.dontDisturb
      ? []
      : [...notifd.notifications].slice(-3).reverse()
    if (notifications.length === 0) {
      setPopupVisible(false)
      return
    }

    clearBox(popupList)
    for (const notification of notifications) {
      const item = history.get(notification.id) ?? snapshot(notification)
      popupList.append(notificationCard(item, notification))
    }
    setPopupVisible(true)
  }
  const notifiedId = notifd.connect('notified', (_service: any, id: number) => {
    const notification = notifd.get_notification(id)
    if (!notification) return
    history.delete(id)
    history.set(id, snapshot(notification))
    while (history.size > 24) history.delete(history.keys().next().value!)
    renderHistory()
    renderPopups()
  })
  const resolvedId = notifd.connect('resolved', () => renderPopups())
  const dndId = notifd.connect('notify::dont-disturb', () => renderPopups())
  const clear = new Gtk.Button({
    cssClasses: ['notification-clear', 'notification-clear-floating'],
    label: 'Clear all',
    halign: Gtk.Align.END,
  })
  clear.connect('clicked', () => {
    const cards: Gtk.Widget[] = []
    let child = historyList.get_first_child()
    while (child) {
      cards.push(child)
      child = child.get_next_sibling()
    }
    if (cards.length === 0) return

    clear.sensitive = false
    const activeNotifications = [...notifd.notifications]
    animateMaterialSpring(
      expressiveMotion.fastSpatial,
      (progress) => {
        cards.forEach((card, index) => {
          const delay = Math.min(index * 0.08, 0.48)
          const cardProgress = Math.min(
            1,
            Math.max(0, (progress - delay) / (1 - delay)),
          )
          card.opacity = 1 - cardProgress
          card.marginStart = Math.round(24 * cardProgress)
        })
        clear.opacity = Math.max(0, 1 - progress * 1.5)
      },
      () => {
        for (const notification of activeNotifications) notification.dismiss()
        history.clear()
        clear.opacity = 1
        clear.sensitive = true
        renderHistory()
        renderPopups()
      },
    )
  })
  historyWidget = new Astal.Box({
    cssClasses: ['notification-history'],
    orientation: Gtk.Orientation.VERTICAL,
    spacing: 12,
    visible: false,
  })
  const historyScroll = new Gtk.ScrolledWindow({
    cssClasses: ['notification-history-scroll'],
    child: historyList,
    hscrollbarPolicy: Gtk.PolicyType.NEVER,
    vscrollbarPolicy: Gtk.PolicyType.AUTOMATIC,
    minContentHeight: 72,
    maxContentHeight: 320,
    propagateNaturalHeight: true,
  })
  historyWidget.append(historyScroll)
  historyWidget.append(clear)
  renderHistory()

  const { TOP, RIGHT } = Astal.WindowAnchor
  popupWindow = new Astal.Window({
    name: `shoji-notifications-${index}`,
    namespace: 'shoji-notifications',
    application: app,
    visible: false,
    gdkmonitor,
    anchor: TOP | RIGHT,
    layer: Astal.Layer.OVERLAY,
    exclusivity: Astal.Exclusivity.IGNORE,
    marginTop: 44,
    marginRight: 12,
    defaultWidth: 380,
    cssClasses: ['NotificationPopupWindow'],
    child: popupList,
  })
  renderPopups()
  popupWindow.connect('destroy', () => {
    stopPopupAnimations()
    notifd.disconnect(notifiedId)
    notifd.disconnect(resolvedId)
    notifd.disconnect(dndId)
  })
  return { popupWindow, historyWidget }
}

function SystemTray() {
  const tray = AstalTray.get_default()
  const box = new Astal.Box({
    cssClasses: ['system-tray'],
    spacing: 6,
  })
  const buttons = new Map<
    string,
    {
      button: Gtk.MenuButton
      item: any
      iconBinding: GObject.Binding
      actionGroupChangedId: number
    }
  >()

  const addItem = (id: string) => {
    if (buttons.has(id)) return

    const item = tray.get_item(id)
    const image = new Gtk.Image({
      cssClasses: ['status-icon', 'tray-icon'],
      pixelSize: 20,
      tooltipText: item.tooltipText || item.title,
    })
    const button = new Gtk.MenuButton({
      cssClasses: ['tray-item'],
      child: image,
      menuModel: item.menuModel,
    })

    const iconBinding = item.bind_property(
      'gicon',
      image,
      'gicon',
      GObject.BindingFlags.SYNC_CREATE,
    )
    // AstalTray defines actions on the tray item separately from its menu
    // model. Install them on the MenuButton (the menu's parent), allowing GTK
    // to own and release the internal PopoverMenu together with the model.
    button.insert_action_group('dbusmenu', item.actionGroup)
    const actionGroupChangedId = item.connect('notify::action-group', () => {
      button.insert_action_group('dbusmenu', item.actionGroup)
    })

    buttons.set(id, {
      button,
      item,
      iconBinding,
      actionGroupChangedId,
    })
    box.append(button)
  }

  const removeItem = (id: string) => {
    const entry = buttons.get(id)
    if (!entry) return

    // A tray item can disappear while its menu is open. Disconnect everything
    // from the remote item before its GMenuModel is destroyed; otherwise GTK
    // can enter a recursive accessibility/action-group notification loop.
    entry.item.disconnect(entry.actionGroupChangedId)
    entry.iconBinding.unbind()
    const popover = entry.button.get_popover()
    popover?.popdown()
    if (popover) popover.visible = false
    entry.button.insert_action_group('dbusmenu', null)
    entry.button.set_menu_model(null)
    box.remove(entry.button)
    entry.button.run_dispose()
    buttons.delete(id)
  }

  for (const item of tray.items) addItem(item.itemId)

  const itemAddedId = tray.connect(
    'item-added',
    (_tray: unknown, id: string) => addItem(id),
  )
  const itemRemovedId = tray.connect(
    'item-removed',
    (_tray: unknown, id: string) => removeItem(id),
  )

  box.connect('destroy', () => {
    tray.disconnect(itemAddedId)
    tray.disconnect(itemRemovedId)
    for (const id of [...buttons.keys()]) removeItem(id)
  })

  return box
}

function SystemIndicators(
  gdkmonitor: Gdk.Monitor,
  index: number,
  notificationHistory: Gtk.Widget,
) {
  const box = new Astal.Box({
    cssClasses: ['system-indicators'],
    spacing: 6,
  })
  const volume = new Gtk.Image({
    cssClasses: ['status-icon', 'volume-icon'],
    iconName: 'audio-volume-medium-symbolic',
    pixelSize: 18,
  })
  const wifi = new Gtk.Image({
    cssClasses: ['status-icon'],
    iconName: 'network-wireless-signal-excellent-symbolic',
    pixelSize: 20,
  })
  const batteryIcon = new Gtk.Image({
    cssClasses: ['status-icon'],
    iconName: 'battery-level-100-symbolic',
    pixelSize: 20,
  })

  const systemState = Variable<SystemState>({
    volume: 50,
    muted: false,
    network: 'offline',
    batteryIcon: 'battery-level-100-symbolic',
    batteryVisible: true,
    brightness: 50,
    wifiEnabled: false,
    bluetoothEnabled: false,
    darkMode: false,
    nightMode: false,
    powerProfile: 'balanced',
  })

  const signalCleanups: Array<() => void> = []
  const updateSystemState = (patch: Partial<SystemState>) => {
    const previous = systemState.get()
    const next = { ...previous, ...patch }
    const changed = Object.keys(patch).some((key) => {
      const field = key as keyof SystemState
      return previous[field] !== next[field]
    })
    if (changed) systemState.set(next)
  }
  const connect = (object: any, signal: string, callback: () => void) => {
    if (!object) return
    const id = object.connect(signal, () => {
      callback()
      // GDBus signal arguments are native GVariants. Collect only after the
      // signal frame has returned so those temporary wrappers are unreachable.
      scheduleGarbageCollection()
    })
    signalCleanups.push(() => object.disconnect(id))
  }

  // Use thin Gio DBus proxies instead of Astal's aggregate services. The
  // latter retain their full object graphs in this GJS process and caused RSS
  // to grow continuously while audio streams and access points changed.
  const network = Gio.DBusProxy.new_for_bus_sync(
    Gio.BusType.SYSTEM,
    Gio.DBusProxyFlags.NONE,
    null,
    'org.freedesktop.NetworkManager',
    '/org/freedesktop/NetworkManager',
    'org.freedesktop.NetworkManager',
    null,
  )
  const updateNetwork = () => {
    const primary = String(network.get_cached_property('PrimaryConnectionType')?.unpack() || '')
    updateSystemState({
      network: primary === '802-11-wireless'
        ? 'wifi'
        : primary === '802-3-ethernet'
          ? 'ethernet'
          : 'offline',
      wifiEnabled: Boolean(network.get_cached_property('WirelessEnabled')?.unpack()),
    })
  }
  updateNetwork()
  connect(network, 'g-properties-changed', updateNetwork)

  const battery = Gio.DBusProxy.new_for_bus_sync(
    Gio.BusType.SYSTEM,
    Gio.DBusProxyFlags.NONE,
    null,
    'org.freedesktop.UPower',
    '/org/freedesktop/UPower/devices/DisplayDevice',
    'org.freedesktop.UPower.Device',
    null,
  )
  const updateBattery = () => updateSystemState({
    batteryIcon: String(battery.get_cached_property('IconName')?.unpack() || 'battery-level-100-symbolic'),
    batteryVisible: Boolean(battery.get_cached_property('IsPresent')?.unpack()),
  })
  updateBattery()
  connect(battery, 'g-properties-changed', updateBattery)

  const interfaceSettings = new Gio.Settings({ schemaId: 'org.gnome.desktop.interface' })
  const updateDarkMode = () => updateSystemState({
    darkMode: interfaceSettings.get_string('color-scheme') === 'prefer-dark',
  })
  updateDarkMode()
  connect(interfaceSettings, 'changed::color-scheme', updateDarkMode)

  const readNumber = (path: string) => {
    try {
      const [, contents] = GLib.file_get_contents(path)
      return Number.parseInt(new TextDecoder().decode(contents).trim(), 10)
    } catch {
      return Number.NaN
    }
  }
  const brightnessPath = '/sys/class/backlight/amdgpu_bl1/brightness'
  const maxBrightness = readNumber('/sys/class/backlight/amdgpu_bl1/max_brightness')
  const updateBrightness = () => {
    const current = readNumber(brightnessPath)
    if (Number.isFinite(current) && Number.isFinite(maxBrightness) && maxBrightness > 0) {
      updateSystemState({ brightness: Math.round(current / maxBrightness * 100) })
    }
  }
  updateBrightness()
  const brightnessMonitor = Gio.File.new_for_path(brightnessPath).monitor_file(
    Gio.FileMonitorFlags.NONE,
    null,
  )
  connect(brightnessMonitor, 'changed', updateBrightness)
  signalCleanups.push(() => brightnessMonitor.cancel())

  const bluetooth = Gio.DBusProxy.new_for_bus_sync(
    Gio.BusType.SYSTEM,
    Gio.DBusProxyFlags.NONE,
    null,
    'org.bluez',
    '/org/bluez/hci0',
    'org.bluez.Adapter1',
    null,
  )
  const updateBluetooth = () => updateSystemState({
    bluetoothEnabled: Boolean(bluetooth.get_cached_property('Powered')?.unpack()),
  })
  updateBluetooth()
  connect(bluetooth, 'g-properties-changed', updateBluetooth)

  const powerProfiles = Gio.DBusProxy.new_for_bus_sync(
    Gio.BusType.SYSTEM,
    Gio.DBusProxyFlags.NONE,
    null,
    'net.hadess.PowerProfiles',
    '/net/hadess/PowerProfiles',
    'net.hadess.PowerProfiles',
    null,
  )
  const updatePowerProfile = () => updateSystemState({
    powerProfile: String(powerProfiles.get_cached_property('ActiveProfile')?.unpack() || 'balanced'),
  })
  updatePowerProfile()
  connect(powerProfiles, 'g-properties-changed', updatePowerProfile)

  const stopIndicators = systemState.subscribe((state) => {
    volume.iconName = state.muted || state.volume < 1
      ? 'audio-volume-muted-symbolic'
      : state.volume < 34
        ? 'audio-volume-low-symbolic'
        : state.volume < 67
          ? 'audio-volume-medium-symbolic'
          : 'audio-volume-high-symbolic'
    wifi.iconName = state.network === 'wifi'
      ? 'network-wireless-signal-excellent-symbolic'
      : state.network === 'ethernet'
        ? 'network-wired-symbolic'
        : 'network-offline-symbolic'
    batteryIcon.iconName = state.batteryIcon
    batteryIcon.visible = state.batteryVisible
  })

  box.append(volume)
  box.append(wifi)
  box.append(batteryIcon)

  const run = (command: string) => {
    void execAsync(['bash', '-lc', command]).catch((error) =>
      console.error(`[shoji-bar] ${String(error)}`),
    )
  }

  const makeScaleRow = (
    iconName: string,
    initialValue: number,
    onChanged: (value: number) => void,
  ) => {
    const row = new Astal.Box({
      cssClasses: ['control-slider-row'],
      spacing: 12,
    })
    const icon = new Gtk.Image({ iconName, pixelSize: 20 })
    const adjustment = new Gtk.Adjustment({
      lower: 0,
      upper: 100,
      stepIncrement: 1,
      pageIncrement: 5,
      value: initialValue,
    })
    const scale = new Gtk.Scale({
      adjustment,
      drawValue: false,
      hexpand: true,
      orientation: Gtk.Orientation.HORIZONTAL,
    })
    let syncing = false
    scale.connect('value-changed', () => {
      if (!syncing) onChanged(scale.get_value())
    })
    row.append(icon)
    row.append(scale)
    return {
      row,
      setValue(value: number) {
        syncing = true
        scale.set_value(value)
        syncing = false
      },
    }
  }

  const volumeSlider = makeScaleRow(
    'audio-volume-high-symbolic',
    50,
    (value) => {
      updateSystemState({ volume: Math.round(value), muted: false })
      run(`wpctl set-volume @DEFAULT_AUDIO_SINK@ ${Math.round(value)}%`)
    },
  )
  const brightnessSlider = makeScaleRow(
    'display-brightness-symbolic',
    50,
    (value) => run(`brightnessctl set ${Math.max(1, Math.round(value))}%`),
  )

  const stopLevels = systemState.subscribe((state) => {
    volumeSlider.setValue(state.volume)
    brightnessSlider.setValue(state.brightness)
  })

  const makeControl = (
    label: string,
    iconName: string,
    command: string,
    isActive: (state: SystemState) => boolean,
  ) => {
    const content = new Astal.Box({ spacing: 10 })
    content.append(new Gtk.Image({ iconName, pixelSize: 20 }))
    content.append(new Gtk.Label({ label, xalign: 0 }))
    const button = new Gtk.Button({
      cssClasses: ['control-tile'],
      child: content,
      hexpand: true,
    })
    button.connect('clicked', () => run(command))
    const stop = systemState.subscribe((state) => {
      const active = isActive(state)
      if (active) button.add_css_class('active')
      else button.remove_css_class('active')
    })
    button.connect('destroy', () => {
      stop()
    })
    return button
  }

  const wifiControl = makeControl(
    'Wi-Fi',
    'network-wireless-symbolic',
    `[ "$(nmcli radio wifi)" = enabled ] && nmcli radio wifi off || nmcli radio wifi on`,
    (state) => state.wifiEnabled,
  )
  const wifiList = new Astal.Box({
    cssClasses: ['wifi-network-list'],
    orientation: Gtk.Orientation.VERTICAL,
    spacing: 4,
  })
  const wifiRevealer = new Gtk.Revealer({
    transitionType: Gtk.RevealerTransitionType.SLIDE_DOWN,
    transitionDuration: 220,
    revealChild: false,
    child: wifiList,
  })
  const clearWifiList = () => {
    let child = wifiList.get_first_child()
    while (child) {
      const next = child.get_next_sibling()
      wifiList.remove(child)
      child.run_dispose()
      child = next
    }
  }
  const shellQuote = (value: string) => `'${value.replaceAll("'", "'\\''")}'`
  const refreshWifiList = async () => {
    clearWifiList()
    wifiList.append(new Gtk.Label({ label: 'ネットワークを検索中…', xalign: 0 }))
    try {
      const output = await execAsync([
        'bash',
        '-lc',
        `nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan yes 2>/dev/null`,
      ])
      clearWifiList()
      const seen = new Set<string>()
      for (const line of output.split('\n')) {
        if (!line) continue
        const [active, ssid, signal = '0', security = ''] = line.split(':')
        if (!ssid || seen.has(ssid)) continue
        seen.add(ssid)
        const row = new Gtk.Button({ cssClasses: ['wifi-network'] })
        const content = new Astal.Box({ spacing: 10 })
        content.append(
          new Gtk.Image({
            iconName:
              Number(signal) >= 65
                ? 'network-wireless-signal-excellent-symbolic'
                : Number(signal) >= 35
                  ? 'network-wireless-signal-good-symbolic'
                  : 'network-wireless-signal-weak-symbolic',
            pixelSize: 18,
          }),
        )
        content.append(new Gtk.Label({ label: ssid, xalign: 0, hexpand: true }))
        content.append(
          new Gtk.Image({
            iconName:
              active === '*'
                ? 'object-select-symbolic'
                : security
                  ? 'changes-prevent-symbolic'
                  : 'changes-allow-symbolic',
            pixelSize: 16,
          }),
        )
        row.child = content
        row.connect('clicked', () => {
          const quoted = shellQuote(ssid)
          run(
            `nmcli connection show ${quoted} >/dev/null 2>&1 && nmcli connection up id ${quoted} || nm-connection-editor`,
          )
        })
        wifiList.append(row)
        if (seen.size >= 6) break
      }
      if (seen.size === 0) {
        wifiList.append(new Gtk.Label({ label: '利用可能なネットワークなし', xalign: 0 }))
      }
      const settings = new Gtk.Button({
        cssClasses: ['wifi-settings'],
        label: 'Wi-Fi の詳細設定',
      })
      settings.connect('clicked', () => run('nm-connection-editor'))
      wifiList.append(settings)
    } catch (error) {
      clearWifiList()
      wifiList.append(new Gtk.Label({ label: 'ネットワークを取得できません', xalign: 0 }))
      console.error(`[shoji-bar] ${String(error)}`)
    }
  }
  const wifiDetails = new Gtk.Button({
    cssClasses: ['wifi-details-button'],
    iconName: 'go-down-symbolic',
    tooltipText: 'Wi-Fi の詳細を表示',
  })
  wifiDetails.connect('clicked', () => {
    wifiRevealer.revealChild = !wifiRevealer.revealChild
    wifiDetails.iconName = wifiRevealer.revealChild
      ? 'go-up-symbolic'
      : 'go-down-symbolic'
    if (wifiRevealer.revealChild) void refreshWifiList()
  })
  const wifiRow = new Astal.Box({ spacing: 8 })
  wifiRow.append(wifiControl)
  wifiRow.append(wifiDetails)
  const bluetoothControl = makeControl(
    'Bluetooth',
    'bluetooth-active-symbolic',
    `bluetoothctl show | grep -q 'Powered: yes' && bluetoothctl power off || bluetoothctl power on`,
    (state) => state.bluetoothEnabled,
  )
  const darkControl = makeControl(
    'Dark mode',
    'weather-clear-night-symbolic',
    `current=$(gsettings get org.gnome.desktop.interface color-scheme); [ "$current" = "'prefer-dark'" ] && gsettings set org.gnome.desktop.interface color-scheme default || gsettings set org.gnome.desktop.interface color-scheme prefer-dark`,
    (state) => state.darkMode,
  )
  const nightControl = makeControl(
    'Night mode',
    'night-light-symbolic',
    `if systemctl --user is-active --quiet shoji-night-light.service; then
       systemctl --user stop shoji-night-light.service
     else
       systemd-run --user --unit=shoji-night-light --collect --property=Restart=on-failure wlsunset -t 3500 -T 6500
     fi`,
    (state) => state.nightMode,
  )
  const powerContent = new Astal.Box({ spacing: 10 })
  const powerIcon = new Gtk.Image({
    iconName: 'power-profile-balanced-symbolic',
    pixelSize: 20,
  })
  const powerLabel = new Gtk.Label({ label: '通常', xalign: 0 })
  powerContent.append(powerIcon)
  powerContent.append(powerLabel)
  const powerControl = new Gtk.Button({
    cssClasses: ['control-tile', 'power-profile-control'],
    child: powerContent,
    hexpand: true,
  })
  powerControl.connect('clicked', () =>
    run(`case "$(powerprofilesctl get 2>/dev/null)" in
      performance) powerprofilesctl set balanced ;;
      balanced) powerprofilesctl set power-saver ;;
      *) powerprofilesctl set performance || powerprofilesctl set balanced ;;
    esac`),
  )
  const stopPowerProfile = systemState.subscribe((state) => {
    const profile = state.powerProfile
    const performance = profile === 'performance'
    const saver = profile === 'power-saver'
    powerLabel.label = performance ? 'パフォーマンス' : saver ? '省電力' : '通常'
    powerIcon.iconName = performance
      ? 'power-profile-performance-symbolic'
      : saver
        ? 'power-profile-power-saver-symbolic'
        : 'power-profile-balanced-symbolic'
    powerControl.remove_css_class('performance')
    powerControl.remove_css_class('power-saver')
    powerControl.add_css_class(performance ? 'performance' : saver ? 'power-saver' : 'balanced')
  })

  const controls = new Astal.Box({
    cssClasses: ['control-center'],
    orientation: Gtk.Orientation.VERTICAL,
    spacing: 12,
  })
  controls.append(brightnessSlider.row)
  controls.append(volumeSlider.row)
  controls.append(wifiRow)
  controls.append(wifiRevealer)
  const rowOne = new Astal.Box({ spacing: 10, homogeneous: true })
  rowOne.append(bluetoothControl)
  rowOne.append(darkControl)
  const rowTwo = new Astal.Box({ spacing: 10, homogeneous: true })
  rowTwo.append(nightControl)
  rowTwo.append(powerControl)
  controls.append(rowOne)
  controls.append(rowTwo)

  const controlCenterLayout = new Astal.Box({
    cssClasses: ['control-center-layout'],
    spacing: 12,
    valign: Gtk.Align.START,
  })
  controlCenterLayout.append(notificationHistory)
  controlCenterLayout.append(controls)

  const { TOP, BOTTOM, LEFT, RIGHT } = Astal.WindowAnchor
  const dismissArea = new Astal.Box({
    cssClasses: ['control-center-dismiss-area'],
    hexpand: true,
    vexpand: true,
  })
  const controlCenterOverlay = new Gtk.Overlay({ child: dismissArea })
  controlCenterLayout.halign = Gtk.Align.END
  controlCenterLayout.marginTop = 40
  controlCenterLayout.marginEnd = 8
  controlCenterOverlay.add_overlay(controlCenterLayout)
  const controlCenter = new Astal.Window({
    name: `shoji-control-center-${index}`,
    namespace: 'shoji-control-center',
    application: app,
    visible: false,
    gdkmonitor,
    anchor: TOP | BOTTOM | LEFT | RIGHT,
    layer: Astal.Layer.OVERLAY,
    exclusivity: Astal.Exclusivity.IGNORE,
    keymode: Astal.Keymode.ON_DEMAND,
    cssClasses: ['ControlCenterWindow'],
    child: controlCenterOverlay,
  })
  let stopSpatialAnimation: (() => void) | undefined
  let stopEffectsAnimation: (() => void) | undefined
  const animationsEnabled = () =>
    Gtk.Settings.get_default()?.gtkEnableAnimations !== false
  const stopAnimations = () => {
    stopSpatialAnimation?.()
    stopEffectsAnimation?.()
    stopSpatialAnimation = undefined
    stopEffectsAnimation = undefined
  }
  const setOpen = (open: boolean) => {
    stopAnimations()
    if (!animationsEnabled()) {
      controlCenterLayout.marginTop = 40
      controlCenterLayout.opacity = 1
      controlCenter.visible = open
      return
    }

    if (open) {
      controlCenterLayout.marginTop = 28
      controlCenterLayout.opacity = 0
      controlCenter.visible = true
      stopSpatialAnimation = animateMaterialSpring(
        expressiveMotion.defaultSpatial,
        (progress) => {
          controlCenterLayout.marginTop = Math.round(28 + 12 * progress)
        },
      )
      stopEffectsAnimation = animateMaterialSpring(
        expressiveMotion.defaultEffects,
        (progress) => {
          controlCenterLayout.opacity = Math.min(1, Math.max(0, progress))
        },
      )
      return
    }

    const startMargin = controlCenterLayout.marginTop
    const startOpacity = controlCenterLayout.opacity
    stopSpatialAnimation = animateMaterialSpring(
      expressiveMotion.fastSpatial,
      (progress) => {
        controlCenterLayout.marginTop = Math.round(
          startMargin + (28 - startMargin) * progress,
        )
      },
    )
    stopEffectsAnimation = animateMaterialSpring(
      expressiveMotion.fastEffects,
      (progress) => {
        controlCenterLayout.opacity = Math.max(0, startOpacity * (1 - progress))
      },
      () => {
        controlCenter.visible = false
        controlCenterLayout.marginTop = 40
        controlCenterLayout.opacity = 1
      },
    )
  }
  controlCenterToggles.set(index, () => setOpen(!controlCenter.visible))
  const outsideClick = new Gtk.GestureClick()
  outsideClick.connect('pressed', () => setOpen(false))
  dismissArea.add_controller(outsideClick)
  const indicatorsButton = new Gtk.Button({
    cssClasses: ['system-indicators-button'],
    child: box,
  })
  indicatorsButton.connect('clicked', () => {
    setOpen(!controlCenter.visible)
  })

  indicatorsButton.connect('destroy', () => {
    controlCenterToggles.delete(index)
    stopAnimations()
    stopIndicators()
    stopLevels()
    stopPowerProfile()
    for (const cleanup of signalCleanups.splice(0)) cleanup()
    systemState.drop()
  })
  return { indicatorsButton, controlCenter }
}

function Bar(gdkmonitor: Gdk.Monitor, index: number) {
  const { TOP, LEFT, RIGHT } = Astal.WindowAnchor
  const { popupWindow, historyWidget } = NotificationUI(gdkmonitor, index)
  const { indicatorsButton, controlCenter } = SystemIndicators(
    gdkmonitor,
    index,
    historyWidget,
  )
  const formatClock = () => {
    const now = new Date()
    const month = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][now.getMonth()]
    return `${month} ${now.getDate()} ${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`
  }
  const clock = new Gtk.Label({
    cssClasses: ['clock'],
    label: formatClock(),
  })
  const clockSource = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 30, () => {
    const label = formatClock()
    if (clock.label !== label) {
      clock.label = label
      scheduleGarbageCollection()
    }
    return GLib.SOURCE_CONTINUE
  })

  const bar = (
    <window
      name={`shoji-bar-${index}`}
      namespace="shoji-bar"
      application={app}
      visible
      gdkmonitor={gdkmonitor}
      anchor={TOP | LEFT | RIGHT}
      exclusivity={Astal.Exclusivity.EXCLUSIVE}
      cssClasses={['Bar']}
      child={
        <centerbox
          cssClasses={['bar-content']}
          endWidget={
            <box cssClasses={['status-cluster']} spacing={9}>
              <box cssClasses={['status-icons']} spacing={6}>
                {SystemTray()}
                {indicatorsButton}
              </box>
              {clock}
            </box>
          }
        />
      }
    />
  )
  bar.connect('destroy', () => GLib.source_remove(clockSource))
  return [bar, controlCenter, popupWindow]
}

app.start({
  instanceName: GLib.getenv('SHOJI_BAR_INSTANCE') ?? 'shoji-bar-2',
  css: style,
  requestHandler(request, respond) {
    const match = request.match(/^control-center toggle(?: (\d+))?$/)
    if (!match) {
      respond('unknown request')
      return
    }

    const monitorIndex = Number(match[1] ?? 0)
    const toggle = controlCenterToggles.get(monitorIndex)
    if (!toggle) {
      respond(`control center ${monitorIndex} not found`)
      return
    }

    toggle()
    respond('ok')
  },
  main() {
    return app
      .get_monitors()
      .flatMap((monitor, index) => index === 0 ? Bar(monitor, index) : [])
  },
})
