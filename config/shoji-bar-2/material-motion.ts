import GLib from 'gi://GLib'

export type MaterialSpring = Readonly<{
  dampingRatio: number
  stiffness: number
}>

// AndroidX Material 3 Expressive MotionScheme values. Spatial springs may
// overshoot; effects springs are critically damped so opacity never does.
export const expressiveMotion = {
  defaultSpatial: { dampingRatio: 0.8, stiffness: 380 },
  fastSpatial: { dampingRatio: 0.6, stiffness: 800 },
  slowSpatial: { dampingRatio: 0.8, stiffness: 200 },
  defaultEffects: { dampingRatio: 1, stiffness: 1600 },
  fastEffects: { dampingRatio: 1, stiffness: 3800 },
  slowEffects: { dampingRatio: 1, stiffness: 800 },
} as const satisfies Record<string, MaterialSpring>

export function springProgress(elapsedMs: number, spring: MaterialSpring) {
  const time = Math.max(0, elapsedMs) / 1000
  const omega = Math.sqrt(spring.stiffness)
  const damping = spring.dampingRatio

  if (damping === 1) {
    return 1 - Math.exp(-omega * time) * (1 + omega * time)
  }

  const dampedOmega = omega * Math.sqrt(1 - damping * damping)
  const envelope = Math.exp(-damping * omega * time)
  return (
    1 -
    envelope *
      (Math.cos(dampedOmega * time) +
        (damping * omega * Math.sin(dampedOmega * time)) / dampedOmega)
  )
}

export function animateMaterialSpring(
  spring: MaterialSpring,
  update: (progress: number) => void,
  complete?: () => void,
) {
  const startedAt = GLib.get_monotonic_time() / 1000
  let source = 0

  source = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 16, () => {
    const elapsed = GLib.get_monotonic_time() / 1000 - startedAt
    const progress = springProgress(elapsed, spring)
    update(progress)

    if (elapsed >= 700 || Math.abs(1 - progress) < 0.001) {
      update(1)
      complete?.()
      return GLib.SOURCE_REMOVE
    }
    return GLib.SOURCE_CONTINUE
  })

  return () => {
    if (source !== 0) {
      GLib.source_remove(source)
      source = 0
    }
  }
}
