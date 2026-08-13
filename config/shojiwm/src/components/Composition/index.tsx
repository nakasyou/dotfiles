import {
  AppIcon,
  Box,
  Button,
  ClientWindow,
  Image,
  ShaderEffect,
  Label,
  WindowBorder,
  backdropSource,
  compileEffect,
  dualKawaseBlur,
  type SSDStyle,
  type WaylandWindow,
  computed,
  useState,
  shaderStage,
  loadShader,
  ManagedWindow,
  read,
  type COMPOSITOR as Compositor,
} from 'shoji_wm'
import type { CompositionRenderable } from 'shoji_wm/types'
import {
  HybridWindowManager,
  TITLEBAR_HEIGHT,
  WINDOW_BORDER_PX,
  WINDOW_STATE_FULLSCREEN,
  WINDOW_STATE_MINIMIZE_VISUAL_IDLE,
  WINDOW_STATE_TILE_DRAGGING,
  WINDOW_STATE_TILE_REORDERING,
  WINDOW_STATE_TILED,
  WINDOW_STATE_VISIBLE_OUTPUTS,
  WINDOW_STATE_RECT,
  WINDOW_STATE_WORKSPACE_VISIBLE,
  WINDOW_STATE_WORKSPACE_OFFSET_Y,
  WINDOW_STATE_WORKSPACE_OPACITY,
} from '../../window-manager'

const FULLSCREEN_Z_INDEX = 2_000_000_000
const FOCUSED_TILED_WINDOW_Z_INDEX = FULLSCREEN_Z_INDEX - 1
const REORDERING_TILED_WINDOW_Z_INDEX = -2_000_000_000

export function setupComposition(
  compositor: typeof Compositor,
  windowManager: HybridWindowManager,
) {
  compositor.window.composition = (window: WaylandWindow) => {
    const decoration = window.decoration()
    const useClientDecoration =
      decoration.mode === 'client' &&
      !(
        decoration.clientPreference === 'server' &&
        decoration.configuredMode === 'server'
      )
    const workspaceVisible = window.state[WINDOW_STATE_WORKSPACE_VISIBLE]
    const workspaceOffsetY = window.state[WINDOW_STATE_WORKSPACE_OFFSET_Y]
    const workspaceOpacity = window.state[WINDOW_STATE_WORKSPACE_OPACITY]
    const tileDragging = window.state[WINDOW_STATE_TILE_DRAGGING]
    const managedRect = computed(() => {
      const rect = window.state[WINDOW_STATE_RECT]()
      return {
        x: read(rect.x),
        y: read(rect.y) + workspaceOffsetY(),
        width: read(rect.width),
        height: read(rect.height),
      }
    })
    const forceRectSize = computed(
      () => window.isResizable() && !window.isTransient(),
    )
    const tiled = computed(
      () => window.appId() === 'mpv' || window.state[WINDOW_STATE_TILED](),
    )
    const stackZIndex = windowManager.getWindowZIndex(window)
    const zIndex = computed(() => {
      if (!window.state[WINDOW_STATE_TILED]()) {
        return stackZIndex()
      }
      if (window.state[WINDOW_STATE_TILE_REORDERING]()) {
        return REORDERING_TILED_WINDOW_Z_INDEX
      }
      return window.isFocused() ? FOCUSED_TILED_WINDOW_Z_INDEX : stackZIndex()
    })
    const minimizeVisualIdle = window.state[WINDOW_STATE_MINIMIZE_VISUAL_IDLE]
    const inactive = computed(
      () => minimizeVisualIdle() || (!workspaceVisible() && !tileDragging()),
    )

    const borderColor = window.isFocused((focused) =>
      focused ? '#d7ba7d' : '#4f5666',
    )
    const titlebarBackground = window.isFocused((focused) =>
      focused ? '#1f243080' : '#2a2f3a80',
    )
    const titleColor = window.isFocused((focused) =>
      focused ? '#f5f7fa' : '#c9d1d9',
    )

    const titlebarStyle: SSDStyle = {
      height: TITLEBAR_HEIGHT,
      paddingX: 8,
      gap: 8,
      alignItems: 'center',
      background: titlebarBackground,
    }

    const backgroundShader = compileEffect({
      input: backdropSource(),
      capturePadding: 24,
      invalidate: { kind: 'on-source-damage-box', damagePadding: 8 },
      pipeline: [
        dualKawaseBlur({ radius: 4, passes: 2 }),
        shaderStage(loadShader('./src/liquid-glass.frag'), {
          uniforms: {
            glass_radius_px: 10.0,
            distortion_depth: 0.2,
            distortion_strength: 0.15,
            chromatic_shift_px: 3.0,
            glass_tint: 0.9,
          },
        }),
      ],
    })

    const titleOnlyShader = compileEffect({
      input: backdropSource(),
      capturePadding: 24,
      invalidate: { kind: 'on-source-damage-box', damagePadding: 8 },
      pipeline: [dualKawaseBlur({ radius: 4, passes: 2 })],
    })

    const appIcon = (
      <AppIcon icon={window.icon} style={{ width: 16, height: 16 }} />
    )
    const label = (
      <Label
        text={window.title}
        style={{
          color: titleColor,
          fontFamily: ['Noto Sans CJK JP', 'Noto Color Emoji'],
          fontSize: 13,
          fontWeight: 600,
          flexGrow: 1,
          flexShrink: 1,
          minWidth: 0,
        }}
      />
    )
    const minimizeButton = <MinimizeButton window={window} />
    const maximizeButton = <MaximizeButton window={window} />
    const closeButton = <CloseButton window={window} />

    let innerComponents = (
      <Box direction="column">
        <ShaderEffect
          shader={titleOnlyShader}
          direction="row"
          style={titlebarStyle}
        >
          {appIcon}
          {label}
          {minimizeButton}
          {maximizeButton}
          {closeButton}
        </ShaderEffect>
        <ClientWindow />
      </Box>
    )

    const TERMINALS = ['kitty', 'ghostty']

    if (TERMINALS.includes(window.appId() ?? '')) {
      innerComponents = (
        <ShaderEffect shader={backgroundShader} direction="column">
          <Box direction="row" style={titlebarStyle}>
            {appIcon}
            {label}
            {minimizeButton}
            {maximizeButton}
            {closeButton}
          </Box>
          <ClientWindow />
        </ShaderEffect>
      )
    }

    // Fullscreen: drop all chrome (titlebar, border, rounded corners) and let
    // the client surface fill its managed rect edge to edge. The rect is set to
    // the whole output by onWindowFullscreenRequest. Rendering nothing but the
    // bare ClientWindow is also what lets the tty backend promote the client
    // buffer to the primary plane (direct scanout).
    if (window.state[WINDOW_STATE_FULLSCREEN]()) {
      return (
        <ManagedWindow
          rect={managedRect}
          zIndex={FULLSCREEN_Z_INDEX}
          visibleOutputs={window.state[WINDOW_STATE_VISIBLE_OUTPUTS]}
          opacity={workspaceOpacity}
          forceRectSize={forceRectSize}
          tiled={tiled}
          idle={inactive}
          interactive={inactive((value) => !value)}
          // Permit low-latency tearing for fullscreen windows. The compositor only actually tears
          // once the window is on the direct-scanout fast path and is committing faster than the
          // refresh rate (i.e. games), so this is a no-op for ordinary fullscreen apps. Narrow it
          // per app if desired, e.g. `allowTearing={isGame(window.appId())}`.
          allowTearing={true}
        >
          <ClientWindow />
        </ManagedWindow>
      )
    }

    if (useClientDecoration) {
      return (
        <ManagedWindow
          rect={managedRect}
          zIndex={zIndex}
          visibleOutputs={window.state[WINDOW_STATE_VISIBLE_OUTPUTS]}
          opacity={workspaceOpacity}
          forceRectSize={forceRectSize}
          tiled={tiled}
          idle={inactive}
          interactive={inactive((value) => !value)}
        >
          <ClientWindow />
        </ManagedWindow>
      )
    }

    return (
      <ManagedWindow
        rect={managedRect}
        zIndex={zIndex}
        visibleOutputs={window.state[WINDOW_STATE_VISIBLE_OUTPUTS]}
        opacity={workspaceOpacity}
        forceRectSize={forceRectSize}
        tiled={tiled}
        idle={inactive}
        interactive={inactive((value) => !value)}
      >
        <WindowBorder
          style={{
            borderRadius: 10,
            background: '#10131900',
            padding: 0,
            paddingX: 0,
            paddingRight: 0,
          }}
          interaction={{
            resizeHitArea: {
              edgePx: 8,
              cornerPx: 14,
            },
          }}
        >
          <Box direction="row">{innerComponents}</Box>
        </WindowBorder>
      </ManagedWindow>
    )
  }
}

const CloseButton = ({ window }: { window: WaylandWindow }) => {
  const [hover, setHover] = useState(false)

  const borderColor = hover((hover) => (hover ? '#00000000' : '#F0808030'))

  var icon: CompositionRenderable | null = null
  if (hover()) {
    icon = (
      <Image
        src="./assets/x.svg"
        style={{
          width: 16,
          height: 16,
          position: 'absolute',
          zIndex: 1,
          pointerEvents: 'none',
        }}
      />
    )
  }

  return (
    <Box style={{ position: 'relative', flexShrink: 0 }}>
      <Button
        onHoverChange={setHover}
        style={{
          width: 16,
          height: 16,
          borderRadius: 8,
          background: '#FFFFFF20',
          border: { px: 1, color: borderColor },
        }}
        onClick={window.close}
      />
      {icon}
    </Box>
  )
}

const MaximizeButton = ({ window }: { window: WaylandWindow }) => {
  const [hover, setHover] = useState(false)

  const borderColor = computed(() => {
    if (!window.isResizable()) {
      return '#00000000'
    }
    return hover() ? '#00000000' : '#00BFFF30'
  })
  const shouldHover = computed(() => hover() && window.isResizable())

  var icon: CompositionRenderable | null = null
  if (shouldHover()) {
    const src = window.isMaximized((maximized) => {
      return maximized ? './assets/minimize-2.svg' : './assets/maximize-2.svg'
    })

    icon = (
      <Image
        src={src}
        style={{
          width: 16,
          height: 16,
          position: 'absolute',
          zIndex: 1,
          pointerEvents: 'none',
        }}
      />
    )
  }

  return (
    <Box style={{ position: 'relative', flexShrink: 0 }}>
      <Button
        onHoverChange={setHover}
        style={{
          width: 32,
          height: 32,
          borderRadius: 8,
          background: '#FFFFFF20',
          border: { px: 1, color: borderColor },
        }}
        onClick={() => {
          if (!read(window.isResizable)) {
            return
          }

          if (read(window.isMaximized)) {
            window.unmaximize()
          } else {
            window.maximize()
          }
        }}
      />
      {icon}
    </Box>
  )
}

const MinimizeButton = ({ window }: { window: WaylandWindow }) => {
  const [hover, setHover] = useState(false)

  const borderColor = hover((hover) => (hover ? '#00000000' : '#F8FF7530'))

  var icon: CompositionRenderable | null = null
  if (hover()) {
    icon = (
      <Image
        src="./assets/minus.svg"
        style={{
          width: 16,
          height: 16,
          position: 'absolute',
          zIndex: 1,
          pointerEvents: 'none',
        }}
      />
    )
  }

  return (
    <Box style={{ position: 'relative', flexShrink: 0 }}>
      <Button
        onHoverChange={setHover}
        style={{
          width: 16,
          height: 16,
          borderRadius: 8,
          background: '#FFFFFF20',
          border: { px: 1, color: borderColor },
        }}
        onClick={() => window.minimize()}
      />
      {icon}
    </Box>
  )
}
