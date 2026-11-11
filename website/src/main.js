import './style.css'

const demo = document.getElementById('demo')
if (demo) {
  // The demo stage is drawn at 2000 x 1260 logical pixels; scale it to the frame.
  const fit = () => demo.style.setProperty('--k', demo.clientWidth / 2000)
  new ResizeObserver(fit).observe(demo)
  fit()

  const root = document.documentElement
  const toggle = document.getElementById('demo-toggle')
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)')
  let pausedByUser = reducedMotion.matches
  let onScreen = true

  // Pausing on the root class keeps the frame and the captions on one timeline.
  const sync = () => {
    root.classList.toggle('demo-paused', pausedByUser || !onScreen)
    toggle.setAttribute('aria-pressed', String(pausedByUser))
    toggle.setAttribute('aria-label', pausedByUser ? 'Play animation' : 'Pause animation')
  }

  toggle.addEventListener('click', () => {
    pausedByUser = !pausedByUser
    sync()
  })

  // No animation work while the frame is scrolled out of view.
  new IntersectionObserver(([entry]) => {
    onScreen = entry.isIntersecting
    sync()
  }).observe(demo)

  sync()
  root.classList.add('demo-ready')
}
