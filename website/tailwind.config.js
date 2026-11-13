/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./privacy-policy.html",
    "./terms.html",
    "./features.html",
    "./teleprompter-for-zoom.html",
    "./read-script-looking-at-camera.html",
    "./hidden-teleprompter-screen-share.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      // Camera green: cream paper and warm ink, with the green of the camera
      // light as the accent. Muted and accent text pass 4.5:1 on paper.
      colors: {
        paper: '#faf7f0',
        ink: { DEFAULT: '#1c1917', soft: '#3f3a36' },
        muted: '#57534e',
        line: '#e7e1d3',
        accent: '#15803d',
      },
    },
  },
  plugins: [],
}
