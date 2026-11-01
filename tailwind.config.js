/** @type {import('tailwindcss').Config} */
export default {
  content: [
    './index.html',
    './src/**/*.{js,ts,jsx,tsx}',
  ],
  theme: {
    extend: {
      colors: {
        brandMain: '#0b0b0b',
        brandSecondary: '#1f1f1f',
        brandHighlight: '#f3f4f6',
        surfaceCard: '#111111',
        surfaceSunken: '#0b0b0b',
        neonLime: '#d4ff3f',
        neonPink: '#ff2dab',
      },
      boxShadow: {
        extruded: '6px 6px 14px #040404, -5px -5px 12px rgba(255, 255, 255, 0.03)',
        'extruded-sm': '4px 4px 10px #040404, -3px -3px 8px rgba(255, 255, 255, 0.03)',
        sunken: 'inset 4px 4px 10px #020202, inset -4px -4px 10px rgba(255, 255, 255, 0.02)',
        'sunken-sm': 'inset 2px 2px 6px #020202, inset -2px -2px 6px rgba(255, 255, 255, 0.02)',
        'glow-pink': '0 0 15px rgba(255, 45, 171, 0.4)',
        'glow-pink-lg': '0 0 25px rgba(255, 45, 171, 0.6)',
        'glow-lime': '0 0 15px rgba(212, 255, 63, 0.4)',
        'glow-lime-lg': '0 0 25px rgba(212, 255, 63, 0.6)',
      },
      fontFamily: {
        display: ['"Space Grotesk"', 'sans-serif'],
        sans: ['"DM Sans"', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'Menlo', 'monospace'],
      },
    },
  },
  plugins: [],
}
