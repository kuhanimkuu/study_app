// Sage, the Study OS mascot — an SVG port of the app's code-drawn
// `SageMascot` (frontend/lib/core/widgets/sage_mascot.dart), same shapes
// and colours on a 100×100 canvas, so the site and the app share one
// character. Keep the two in step if Sage changes.

export type SageMood = 'happy' | 'cheer' | 'thinking'

type Props = {
  size?: number
  mood?: SageMood
  className?: string
  title?: string
}

const INK = '#111A33'

export default function Sage({ size = 96, mood = 'happy', className, title = 'Sage, the Study OS mascot' }: Props) {
  const look = mood === 'thinking' ? { x: -3, y: -3.5 } : { x: 0, y: 1 }
  return (
    <svg width={size} height={size} viewBox="0 0 100 100" className={className} role="img" aria-label={title}>
      {/* body, on its darker ledge */}
      <rect x="10" y="29.5" width="80" height="70" rx="36" fill="#1A44A8" />
      <rect x="10" y="26" width="80" height="70" rx="36" fill="#2F6FED" />
      <ellipse cx="50" cy="77" rx="23" ry="15" fill="#5B92FF" />
      {/* cheeks */}
      <ellipse cx="24" cy="62" rx="6.5" ry="4" fill="#FF8FB1" opacity="0.75" />
      <ellipse cx="76" cy="62" rx="6.5" ry="4" fill="#FF8FB1" opacity="0.75" />

      {mood === 'cheer' ? (
        <g fill="none" stroke={INK} strokeWidth="4.5" strokeLinecap="round">
          <path d="M 27.87 49.99 A 7.5 6.5 0 0 1 42.13 49.99" />
          <path d="M 57.87 49.99 A 7.5 6.5 0 0 1 72.13 49.99" />
        </g>
      ) : (
        [35, 65].map((cx) => (
          <g key={cx}>
            <circle cx={cx} cy="50" r="10.5" fill="#fff" />
            <circle cx={cx + look.x} cy={50 + look.y} r="5.8" fill={INK} />
            <circle cx={cx + look.x + 2} cy={50 + look.y - 2.2} r="1.9" fill="#fff" />
          </g>
        ))
      )}

      {mood === 'cheer' ? (
        <>
          <path d="M 41 65.5 Q 50 79.5 59 65.5 Z" fill="#7A1D35" />
          <ellipse cx="50" cy="71.5" rx="4" ry="2" fill="#FF6F91" />
        </>
      ) : (
        <path
          d={mood === 'thinking' ? 'M 53.56 68.54 A 4 4.5 0 0 1 46.44 68.54' : 'M 56.24 68.54 A 7 4.5 0 0 1 43.76 68.54'}
          fill="none"
          stroke={INK}
          strokeWidth="3.5"
          strokeLinecap="round"
        />
      )}

      {/* graduation cap, with a light rim so it reads on dark backgrounds */}
      <rect x="33" y="20" width="34" height="11" rx="3" fill="#1B2440" stroke="#7E95D6" strokeWidth="1.8" paintOrder="stroke" />
      <path d="M 50 4 L 86 17 L 50 30 L 14 17 Z" fill="#1B2440" stroke="#7E95D6" strokeWidth="1.8" strokeLinejoin="round" />
      <path d="M 50 17 L 80 21 L 80 34" fill="none" stroke="#FF8A00" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
      <circle cx="80" cy="36" r="3" fill="#FF8A00" />
    </svg>
  )
}
