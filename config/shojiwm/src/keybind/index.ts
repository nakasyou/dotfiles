import type { COMPOSITOR as Compositor } from 'shoji_wm'
import { HYBRID_WINDOW_MANAGER, scheduleWorkspaceBroadcast } from '../index.tsx'

export function setupKeybind(compositor: typeof Compositor) {
  compositor.key.bind(
    'launcher',
    'Super+A',
    () => {
      compositor.process.spawn({
        command: [
          '/home/nakasyou/.local/state/nix/profiles/home-manager/home-path/bin/vicinae',
          'open',
        ],
      })
    },
  )

  compositor.key.bind('terminal', 'Super+T', () => {
    compositor.process.spawn({ command: ['ghostty'] })
  })

  compositor.key.bind('dolphin', 'Super+E', () => {
    compositor.process.spawn({ command: 'dolphin' })
  })

  compositor.key.bind('play', 'XF86AudioPlay', () => {
    compositor.process.spawn({ command: 'playerctl play-pause' })
  })
  compositor.key.bind('pause', 'XF86AudioPause', () => {
    compositor.process.spawn({ command: 'playerctl play-pause' })
  })
  compositor.key.bind('next', 'XF86AudioNext', () => {
    compositor.process.spawn({ command: 'playerctl next' })
  })
  compositor.key.bind('prev', 'XF86AudioPrev', () => {
    compositor.process.spawn({ command: 'playerctl previous' })
  })

  compositor.key.bind('clipboard', 'Super+V', () => {
    const monitor = HYBRID_WINDOW_MANAGER.getCurrentMonitorName()
    compositor.process.spawn({
      command: ['ags', 'request', '-i', 'ags', 'clipboard', 'toggle', monitor],
    })
  })
  compositor.key.bind('control-center', 'Super+C', () => {
    compositor.process.spawn({
      command: [
        'ags',
        'request',
        '-i',
        'shoji-bar-2',
        'control-center toggle 0',
      ],
    })
  })
  compositor.key.bind('screenshot', 'Super+P', () => {
    compositor.process.spawn({
      command: [
        '/home/nakasyou/.local/state/nix/profiles/home-manager/home-path/bin/shoji-screenshot',
        'region',
      ],
    })
  })
  compositor.key.bind('screenshot-standard', 'Super+Shift+S', () => {
    compositor.process.spawn({
      command: [
        '/home/nakasyou/.local/state/nix/profiles/home-manager/home-path/bin/shoji-screenshot',
        'region',
      ],
    })
  })
  compositor.key.bind('screenshot-freeze', 'Super+Ctrl+P', () => {
    compositor.process.spawn({
      command: [
        '/home/nakasyou/.local/state/nix/profiles/home-manager/home-path/bin/shoji-screenshot',
        'region',
      ],
    })
  })

  compositor.key.bind('reload-shoji-bar', 'Super+Ctrl+Shift+R', () => {
    compositor.process.spawn({
      command: ['ags', 'quit', '-i', 'shoji-bar-2'],
    })
  })

  compositor.key.bind('toggle-tiling-mode', 'Super+S', () => {
    HYBRID_WINDOW_MANAGER.toggleCurrentWorkspaceTiling()
    scheduleWorkspaceBroadcast()
  })
  compositor.key.bind('close-focused-window', 'Super+Q', () => {
    HYBRID_WINDOW_MANAGER.closeFocusedWindow()
  })
  compositor.key.bind('toggle-focused-window-maximize', 'Super+M', () => {
    HYBRID_WINDOW_MANAGER.toggleFocusedWindowMaximize()
  })
  compositor.key.bind('switch-window', 'Alt+Tab', () => {
    HYBRID_WINDOW_MANAGER.cycleFocusedWindow(1)
  })
  compositor.key.bind('switch-window-backward', 'Alt+Shift+Tab', () => {
    HYBRID_WINDOW_MANAGER.cycleFocusedWindow(-1)
  })
  compositor.key.bind('tile-focus-left-quick', 'Super+Left', () => {
    HYBRID_WINDOW_MANAGER.focusTile(-1)
  })
  compositor.key.bind('tile-focus-right-quick', 'Super+Right', () => {
    HYBRID_WINDOW_MANAGER.focusTile(1)
  })
  compositor.key.bind('tile-focus-left', 'Super+Ctrl+Left', () => {
    HYBRID_WINDOW_MANAGER.focusTile(-1)
  })
  compositor.key.bind('tile-focus-right', 'Super+Ctrl+Right', () => {
    HYBRID_WINDOW_MANAGER.focusTile(1)
  })
  compositor.key.bind('tile-move-left', 'Super+Shift+Left', () => {
    HYBRID_WINDOW_MANAGER.moveFocusedTile(-1)
    scheduleWorkspaceBroadcast()
  })
  compositor.key.bind('tile-move-right', 'Super+Shift+Right', () => {
    HYBRID_WINDOW_MANAGER.moveFocusedTile(1)
    scheduleWorkspaceBroadcast()
  })
  compositor.key.bind('window-move-workspace-prev', 'Super+Shift+Up', () => {
    HYBRID_WINDOW_MANAGER.moveFocusedWindowToWorkspace(-1)
    scheduleWorkspaceBroadcast()
  })
  compositor.key.bind('window-move-workspace-next', 'Super+Shift+Down', () => {
    HYBRID_WINDOW_MANAGER.moveFocusedWindowToWorkspace(1)
    scheduleWorkspaceBroadcast()
  })
  compositor.key.bind('workspace-prev', 'Super+Ctrl+Up', () => {
    HYBRID_WINDOW_MANAGER.switchWorkspace(-1)
    scheduleWorkspaceBroadcast()
  })
  compositor.key.bind('workspace-next', 'Super+Ctrl+Down', () => {
    HYBRID_WINDOW_MANAGER.switchWorkspace(1)
    scheduleWorkspaceBroadcast()
  })

  let fpsCounter = false
  compositor.key.bind('fps', 'Super+Shift+F', () => {
    fpsCounter = !fpsCounter
    compositor.debug.fpsCounter = fpsCounter
  })

  let profileEnabled = false
  compositor.key.bind('profile', 'Super+Shift+T', () => {
    profileEnabled = !profileEnabled
    compositor.debug.enableProfile(profileEnabled)
  })
}
