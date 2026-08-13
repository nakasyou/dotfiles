import {
  COMPOSITOR,
  backdropSource,
  compileEffect,
  compileLayerEffect,
  dualKawaseBlur,
  type WaylandWindow,
  shaderStage,
  loadShader,
  layerSource,
  type DisplayConfigDraft,
  compilePopupEffect,
  popupSource,
} from 'shoji_wm'
import type { ManagedWindowRect } from 'shoji_wm/types'
import { createIpcServer } from 'shoji_wm/ipc'
import { setupKeybind } from './keybind/index.ts'
import { setupComposition } from './components/Composition/index.tsx'
import {
  HybridWindowManager,
  TITLEBAR_HEIGHT,
  WINDOW_BORDER_PX,
  WINDOW_STATE_MINIMIZED,
} from './window-manager'

COMPOSITOR.env.apply({
  QT_QPA_PLATFORM: 'wayland;xcb',
  QT_QPA_PLATFORMTHEME: 'qt6ct',
  QT_IM_MODULE: 'fcitx',
  XMODIFIERS: '@im=fcitx',
  SDL_IM_MODULE: 'fcitx',
  GLFW_IM_MODULE: 'ibus',
  ELECTRON_OZONE_PLATFORM_HINT: 'wayland',
})
COMPOSITOR.env.publish()

COMPOSITOR.cursor.configure({
  theme: 'Adwaita',
  size: 24,
})

COMPOSITOR.window.decoration.configure((_window, context) => {
  // Match GNOME's behavior: honor the client's decoration preference and
  // default to client-side decoration when it does not express one.
  return { mode: context.clientPreference ?? 'client' }
})

export const HYBRID_WINDOW_MANAGER = new HybridWindowManager(naturalRootRect)
const HOT_RELOAD_WINDOW_MANAGER_STATE = 'config.hybrid-window-manager'

COMPOSITOR.onDisable((event) => {
  if (event.isReloading) {
    const snapshot = HYBRID_WINDOW_MANAGER.snapshot()
    event.persist(HOT_RELOAD_WINDOW_MANAGER_STATE, snapshot)
  }
  HYBRID_WINDOW_MANAGER.dispose()
})

COMPOSITOR.onEnable((event) => {
  if (event.isReloading) {
    const snapshot = event.restore<
      ReturnType<typeof HYBRID_WINDOW_MANAGER.snapshot>
    >(HOT_RELOAD_WINDOW_MANAGER_STATE)
    if (snapshot) {
      HYBRID_WINDOW_MANAGER.restore(snapshot)
    }
  }
})

// ---------------------------------------------------------------------------
// External IPC: expose the workspace layout to clients such as the bar.
//   workspaces.get           -> WorkspacesView                     (request/response)
//   workspaces.switch        { direction: -1 | 1 }                 (command)
//   workspaces.activate      { monitor: string, index: number }    (command)
//   workspaces.toggleTiling  { monitor?: string }                  (command)
//   workspaces.changed       -> WorkspacesView                     (broadcast)
//   windows.activate         { windowId: string }                  (command)
//   dock.proximity           { monitor: string, inside: bool }    (broadcast)
// ---------------------------------------------------------------------------
const WORKSPACE_IPC = createIpcServer()
let lastWorkspacesJson = ''
let workspaceBroadcastQueued = false

function broadcastWorkspaces() {
  const view = HYBRID_WINDOW_MANAGER.viewForIpc()
  const json = JSON.stringify(view)
  if (json === lastWorkspacesJson) {
    return
  }
  lastWorkspacesJson = json
  WORKSPACE_IPC.broadcast('workspaces.changed', view)
}

function reconfigureProtocolWorkspaces() {
  COMPOSITOR.workspace.reconfigure()
}

// Coalesce many state mutations within one tick into a single diffed broadcast.
export function scheduleWorkspaceBroadcast() {
  // Protocol state must be staged before the current runtime response is
  // written; otherwise key bindings/Waybar activations only reach external
  // bars on a later, unrelated runtime request.
  reconfigureProtocolWorkspaces()
  if (workspaceBroadcastQueued) {
    return
  }
  workspaceBroadcastQueued = true
  void Promise.resolve().then(() => {
    workspaceBroadcastQueued = false
    broadcastWorkspaces()
  })
}

COMPOSITOR.workspace.configure(() => {
  const view = HYBRID_WINDOW_MANAGER.viewForIpc()
  return {
    groups: view.monitors.map((monitor) => ({
      id: monitor.name,
      outputs: [monitor.name],
      workspaces: monitor.workspaces.map((workspace) => ({
        id: `${monitor.name}:${workspace.index}`,
        name: String(workspace.index),
        coordinates: [Math.max(0, workspace.index - 1)],
        active: workspace.active,
        hidden: !workspace.active && workspace.windowCount === 0,
      })),
    })),
  }
})

COMPOSITOR.workspace.event.onActivate((event) => {
  const [monitor, rawIndex] = event.workspaceId.split(':')
  const index = Number(rawIndex)
  if (!monitor || !Number.isInteger(index) || index < 1) {
    return
  }
  HYBRID_WINDOW_MANAGER.activate(monitor, index)
  scheduleWorkspaceBroadcast()
})

WORKSPACE_IPC.handle('workspaces.get', () => HYBRID_WINDOW_MANAGER.viewForIpc())
WORKSPACE_IPC.handle('workspaces.switch', (params) => {
  const direction = (params as { direction?: number } | undefined)?.direction
  HYBRID_WINDOW_MANAGER.switchWorkspace(direction === -1 ? -1 : 1)
  scheduleWorkspaceBroadcast()
})
WORKSPACE_IPC.handle('workspaces.activate', (params) => {
  const request = params as { monitor?: string; index?: number } | undefined
  if (request?.monitor && typeof request.index === 'number') {
    HYBRID_WINDOW_MANAGER.activate(request.monitor, request.index)
    scheduleWorkspaceBroadcast()
  }
})
WORKSPACE_IPC.handle('workspaces.toggleTiling', (params) => {
  const monitor = (params as { monitor?: string } | undefined)?.monitor
  if (monitor) {
    HYBRID_WINDOW_MANAGER.toggleWorkspaceTilingForMonitor(monitor)
  } else {
    HYBRID_WINDOW_MANAGER.toggleCurrentWorkspaceTiling()
  }
  scheduleWorkspaceBroadcast()
})
WORKSPACE_IPC.handle('windows.activate', (params) => {
  const windowId = (params as { windowId?: string } | undefined)?.windowId
  if (typeof windowId === 'string') {
    HYBRID_WINDOW_MANAGER.activateWindowById(windowId)
    scheduleWorkspaceBroadcast()
  }
})

// ---------------------------------------------------------------------------
// Dock proximity: watch the pointer and broadcast enter/leave for the bottom
// strip of each monitor. The bar uses this in place of a layer-shell trigger
// surface (which would otherwise capture clicks meant for the windows below).
// ---------------------------------------------------------------------------
// Two thresholds with hysteresis:
//   - SHOW: pointer must be in the bottom 10px to trigger reveal
//   - HIDE: once visible, pointer must leave the bottom 120px to dismiss
// This gives a precise "reach for the dock" trigger while keeping the dock
// stable once the user is interacting with it (so brushing the cursor a few
// dozen pixels above the dock body does not flicker it away).
const DOCK_SHOW_ZONE_PX = 10
const DOCK_HIDE_ZONE_PX = 120
const dockProximityByMonitor = new Map<string, boolean>()

function pointerInBottomStrip(
  monitor: string,
  pointerX: number,
  pointerY: number,
  stripPx: number,
): boolean {
  const output = COMPOSITOR.output.get(monitor)
  if (!output || !output.resolution) {
    return false
  }
  const width = output.resolution.width / output.scale
  const height = output.resolution.height / output.scale
  const left = output.position.x
  const top = output.position.y
  const right = left + width
  const bottom = top + height
  return (
    pointerX >= left &&
    pointerX < right &&
    pointerY >= bottom - stripPx &&
    pointerY < bottom
  )
}

function nextDockProximity(
  monitor: string,
  pointerX: number,
  pointerY: number,
  onTrackedMonitor: boolean,
): boolean {
  if (!onTrackedMonitor) return false
  const wasInside = dockProximityByMonitor.get(monitor) === true
  // While outside, only the narrow show-zone counts (10px).
  // While inside, the wide hide-zone keeps it open (120px).
  return pointerInBottomStrip(
    monitor,
    pointerX,
    pointerY,
    wasInside ? DOCK_HIDE_ZONE_PX : DOCK_SHOW_ZONE_PX,
  )
}

function updateDockProximity(monitor: string, inside: boolean) {
  if (dockProximityByMonitor.get(monitor) === inside) {
    return
  }
  dockProximityByMonitor.set(monitor, inside)
  WORKSPACE_IPC.broadcast('dock.proximity', { monitor, inside })
}

// Snap-zone preview: broadcast the active snap rect (floating edge zones, or the
// opened tiling slot) to the bar, which renders the rounded preview overlay.
//   snap.preview  { monitor, rect: {x,y,w,h} | null, kind: "floating"|"tiling" }
let lastSnapJson = ''
HYBRID_WINDOW_MANAGER.setSnapPreviewBroadcaster((preview) => {
  const json = JSON.stringify(preview)
  if (json === lastSnapJson) {
    return
  }
  lastSnapJson = json
  WORKSPACE_IPC.broadcast('snap.preview', preview)
})

HYBRID_WINDOW_MANAGER.setWorkspaceChangeBroadcaster(() => {
  scheduleWorkspaceBroadcast()
})

COMPOSITOR.onDisable(() => {
  WORKSPACE_IPC.close()
})

COMPOSITOR.process.once('fcitx5', {
  command: 'fcitx5 -d',
  runPolicy: 'once-per-session',
})

// GTK_A11Y=none disables the AT-SPI accessibility bridge for the bar. A status
// bar never needs a screen reader, and GTK 4.22's accessibility relation
// handling can melt down into a recursive notify storm (100% CPU) when a
// GMenuModel-backed popover's model is destroyed while open — e.g. quitting an
// app from its system-tray menu. Must be set before GTK init, hence here.
COMPOSITOR.process.service('wallpaper', {
  command: [
    '/etc/profiles/per-user/nakasyou/bin/swaybg',
    '-i',
    '/home/nakasyou/.config/shoji-bar-2/assets/background.jpg',
    '-m',
    'fill',
  ],
  restart: 'on-exit',
  reload: 'keep-if-unchanged',
})

COMPOSITOR.process.service('shoji-bar', {
  command: [
    '/run/current-system/sw/bin/bash',
    '/home/nakasyou/.config/shoji-bar-2/start.sh',
  ],
  cwd: '/home/nakasyou/.config/shoji-bar-2',
  env: {
    GTK_A11Y: 'none',
    GSK_RENDERER: 'cairo',
  },
  restart: 'on-exit',
  reload: 'keep-if-unchanged',
})

COMPOSITOR.process.service('network-indicator', {
  command: ['/etc/profiles/per-user/nakasyou/bin/nm-applet', '--indicator'],
  restart: 'on-failure',
  reload: 'keep-if-unchanged',
})

COMPOSITOR.process.service('bluetooth-indicator', {
  command: ['/run/current-system/sw/bin/blueman-applet'],
  restart: 'on-failure',
  reload: 'keep-if-unchanged',
})
// cliphist clipboard history watchers. Text and image need separate watchers;
// run as services so they are restarted if they ever exit.
COMPOSITOR.process.service('cliphist-text', {
  command: ['wl-paste', '--type', 'text', '--watch', 'cliphist', 'store'],
  restart: 'on-exit',
})
COMPOSITOR.process.service('cliphist-image', {
  command: ['wl-paste', '--type', 'image', '--watch', 'cliphist', 'store'],
  restart: 'on-exit',
})

setupKeybind(COMPOSITOR)

COMPOSITOR.output.configure((_context) => {
  const display: DisplayConfigDraft = {}

  display['eDP-1'] = {
    mode: 'extend',
    resolution: 'best',
    position: { x: 0, y: 1080 },
    scale: 1.0,
  }
  display['eDP-2'] = {
    mode: 'extend',
    resolution: 'best',
    position: { x: 0, y: 1080 },
    scale: 1.0,
  }
  display['HDMI-A-1'] = {
    mode: 'extend',
    resolution: 'best',
    position: { x: 0, y: 0 },
    scale: 1.0,
  }
  display['DP-1'] = {
    mode: 'extend',
    resolution: 'best',
    position: 'auto',
    scale: 1.0,
  }
  display['DP-4'] = {
    mode: 'extend',
    resolution: 'best',
    position: 'auto',
    scale: 1.0,
  }
  display['DP-2'] = {
    mode: 'extend',
    resolution: 'best',
    position: 'auto',
    scale: 1.0,
  }

  return display
})

COMPOSITOR.input.configure((input, _context) => {
  input.global = {
    touchpad: {
      tapToClick: true,
      naturalScroll: true,
      scrollMethod: 'twoFinger',
      disableWhileTyping: true,
      scrollFactor: 0.3,
    },
    pointer: {
      pointerAccel: 0.3,
      accelProfile: 'adaptive',
    },
    keyboard: {
      model: 'jp106',
      layout: 'jp',
      options: 'caps:ctrl_modifier',
      repeatRate: 60,
      repeatDelay: 250,
    },
  }
})

HYBRID_WINDOW_MANAGER.configureWorkspaceGestureSpeed({
  workspaceScrollFactor: 1.5,
  workspaceScrollKineticFactor: 1,
  workspaceSwitchFactor: 1,
  workspaceSwitchVelocityFactor: 1,
})

COMPOSITOR.effect.background_effect = compileEffect({
  input: backdropSource(),
  capturePadding: 24,
  invalidate: { kind: 'on-source-damage-box', damagePadding: 8 },
  pipeline: [dualKawaseBlur({ radius: 4, passes: 2 })],
})

const LAYER_BLUR_MASK = compileLayerEffect({
  input: backdropSource(),
  capturePadding: 24,
  invalidate: { kind: 'on-source-damage-box', damagePadding: 8 },
  alpha: 'preserve',
  pipeline: [
    dualKawaseBlur({ radius: 4, passes: 2 }),
    shaderStage(loadShader('./src/layer-blur-mask.frag'), {
      textures: {
        layer_mask: layerSource(),
      },
      uniforms: {
        opacity_threshold: 0.25,
        mask_feather: 0.04,
      },
    }),
  ],
})

// The bar intentionally uses a 20%-opaque Material primary-container tint.
// Give it a lower alpha threshold than other layer-shell surfaces so its
// rounded translucent background still reveals the compositor blur.
const SHOJI_BAR_GLASS = compileLayerEffect({
  input: backdropSource(),
  capturePadding: 24,
  invalidate: { kind: 'on-source-damage-box', damagePadding: 8 },
  alpha: 'preserve',
  pipeline: [
    dualKawaseBlur({ radius: 4, passes: 2 }),
    shaderStage(loadShader('./src/liquid-glass.frag'), {
      uniforms: {
        glass_radius_px: 16.0,
        distortion_depth: 0.28,
        distortion_strength: 0.1,
        chromatic_shift_px: 1.25,
        glass_tint: 1.03,
      },
    }),
    shaderStage(loadShader('./src/layer-blur-mask.frag'), {
      textures: {
        layer_mask: layerSource(),
      },
      uniforms: {
        opacity_threshold: 0.12,
        mask_feather: 0.04,
      },
    }),
  ],
})

COMPOSITOR.effect.layer = (layer) => {
  if (layer.namespace() === 'no_blur') {
    return {}
  }

  if (layer.namespace() === 'shoji-bar') {
    return {
      behind: SHOJI_BAR_GLASS,
    }
  }

  return {
    behind: LAYER_BLUR_MASK,
  }
}

const POPUP_BLUR = compilePopupEffect({
  input: backdropSource(),
  capturePadding: 4 * 2 * 2 + 24 + 32,
  invalidate: { kind: 'on-source-damage-box', damagePadding: 8 },
  // The mask stage intentionally outputs transparency (the blur is clipped
  // to the layer's own alpha), so the pipeline's alpha must survive the
  // finish/display passes instead of being forced opaque.
  alpha: 'preserve',
  pipeline: [
    dualKawaseBlur({ radius: 4, passes: 2 }),
    shaderStage(loadShader('./src/layer-blur-mask.frag'), {
      textures: {
        layer_mask: popupSource(),
      },
      uniforms: {
        opacity_threshold: 0.25,
        mask_feather: 0.04,
      },
    }),
  ],
})

COMPOSITOR.effect.popup = (popup) => {
  if (popup.parentKind === 'window') {
    return {}
  }

  return {
    behind: POPUP_BLUR,
  }
}

// GTK3 tooltips (waybar) declare their whole rect opaque despite transparent
// rounded corners, which paints the corners as a solid fill and culls the
// behind-blur. Ignore the declaration for layer-shell popups.
COMPOSITOR.rendering.surfacePolicy = (surface) => {
  if (surface.kind === 'popup' && surface.parentKind === 'layer') {
    return { opaqueRegion: 'ignore' }
  }
  return null
}

COMPOSITOR.event.onOpen((window) => {
  HYBRID_WINDOW_MANAGER.onOpen(window)
})

COMPOSITOR.event.onInitialConfigure((window) => {
  HYBRID_WINDOW_MANAGER.onInitialConfigure(window)
})

COMPOSITOR.event.onFirstCommit((window) => {
  HYBRID_WINDOW_MANAGER.onFirstCommit(window)
  scheduleWorkspaceBroadcast()
})

COMPOSITOR.event.onStartClose((window) => {
  HYBRID_WINDOW_MANAGER.onStartClose(window)
  scheduleWorkspaceBroadcast()
})

COMPOSITOR.event.onClose((window) => {
  HYBRID_WINDOW_MANAGER.onClose(window)
  scheduleWorkspaceBroadcast()
})

COMPOSITOR.event.onFocus((window, focused) => {
  HYBRID_WINDOW_MANAGER.onFocus(window, focused)
  if (focused) {
    HYBRID_WINDOW_MANAGER.recordFocus(window.id)
    scheduleWorkspaceBroadcast()
  }
})

COMPOSITOR.event.onPointerMove((event) => {
  HYBRID_WINDOW_MANAGER.onPointerMove(event)

  // Dock proximity: update only the monitor the pointer is currently on,
  // and emit "leave" for other monitors that were previously inside. The
  // narrow/wide threshold is hysteretic per current state.
  const pointerX = event.position.x
  const pointerY = event.position.y
  for (const monitor of COMPOSITOR.output.list) {
    const inside = nextDockProximity(
      monitor,
      pointerX,
      pointerY,
      monitor === event.outputName,
    )
    updateDockProximity(monitor, inside)
  }
})

COMPOSITOR.event.onGestureSwipe((event) => {
  HYBRID_WINDOW_MANAGER.onGestureSwipe(event)
  scheduleWorkspaceBroadcast()
})

COMPOSITOR.event.onOutputChange((event) => {
  HYBRID_WINDOW_MANAGER.onOutputChange(event)
  scheduleWorkspaceBroadcast()
})

COMPOSITOR.event.onCreateLayer(() => {
  HYBRID_WINDOW_MANAGER.refreshUsableAreaLayouts()
})

COMPOSITOR.event.onUpdateLayer(() => {
  HYBRID_WINDOW_MANAGER.refreshUsableAreaLayouts()
})

COMPOSITOR.event.onDestroyLayer(() => {
  HYBRID_WINDOW_MANAGER.refreshUsableAreaLayouts()
})

COMPOSITOR.event.onWindowResize((event) => {
  HYBRID_WINDOW_MANAGER.onWindowResize(event)
})

COMPOSITOR.pointer.bindWindowMoveModifier('Super')
COMPOSITOR.pointer.bindWindowResizeModifier('Super')

COMPOSITOR.event.onWindowMove((event) => {
  HYBRID_WINDOW_MANAGER.onWindowMove(event)
})

COMPOSITOR.event.onWindowMaximizeRequest((event) => {
  HYBRID_WINDOW_MANAGER.onWindowMaximizeRequest(event)
})

COMPOSITOR.event.onWindowMinimizeRequest((event) => {
  HYBRID_WINDOW_MANAGER.onWindowMinimizeRequest(event)
})

COMPOSITOR.event.onWindowFullscreenRequest((event) => {
  HYBRID_WINDOW_MANAGER.onWindowFullscreenRequest(event)
})

COMPOSITOR.event.onWindowActivateRequest((event) => {
  HYBRID_WINDOW_MANAGER.onWindowActivateRequest(event)
  scheduleWorkspaceBroadcast()
})

function naturalRootRect(window: WaylandWindow): ManagedWindowRect {
  const client = window.position
  return {
    x: client.x - WINDOW_BORDER_PX,
    y: client.y - TITLEBAR_HEIGHT - WINDOW_BORDER_PX,
    width: client.width + WINDOW_BORDER_PX * 2,
    height: client.height + TITLEBAR_HEIGHT + WINDOW_BORDER_PX * 2,
  }
}

setupComposition(COMPOSITOR, HYBRID_WINDOW_MANAGER)
export default COMPOSITOR
