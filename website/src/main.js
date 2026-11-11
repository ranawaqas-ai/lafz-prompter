import './style.css'

// The demo stage is drawn at 2000 x 1260 logical pixels; scale it to the frame.
const demo = document.getElementById('demo')
if (demo) {
  const fit = () => demo.style.setProperty('--k', demo.clientWidth / 2000)
  new ResizeObserver(fit).observe(demo)
  fit()
}
