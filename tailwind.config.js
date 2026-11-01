/** @type {import('tailwindcss').Config} */
export default {
  content: [
    './index.html',
    './src/**/*.{js,ts,jsx,tsx}',
  ],
  theme: {
    extend: {
      colors: {
        brandMain: '#080a0f',
        brandSecondary: '#0b0e14',
        brandHighlight: '#f3f4f6',
        surfaceCard: '#11151f',
        surfaceSunken: '#090c12',
        neonLime: '#d4ff3f',
        neonPink: '#f43f5e',
      },
      boxShadow: {
        extruded: '6px 6px 16px rgba(0, 0, 0, 0.7), -3px -3px 8px rgba(255, 255, 255, 0.025)',
        'extruded-sm': '4px 4px 10px rgba(0, 0, 0, 0.7), -2px -2px 6px rgba(255, 255, 255, 0.025)',
        sunken: 'inset 3px 3px 6px rgba(0, 0, 0, 0.75), inset -2px -2px 5px rgba(255, 255, 255, 0.025)',
        'sunken-sm': 'inset 2px 2px 4px rgba(0, 0, 0, 0.75), inset -1px -1px 3px rgba(255, 255, 255, 0.025)',
        'glow-pink': '0 0 16px -2px rgba(244, 63, 94, 0.45)',
        'glow-pink-lg': '0 0 24px -2px rgba(244, 63, 94, 0.65)',
        'glow-lime': '0 0 16px -2px rgba(212, 255, 63, 0.45)',
        'glow-lime-lg': '0 0 24px -2px rgba(212, 255, 63, 0.65)',
      },
      fontFamily: {
        display: ['"Space Grotesk"', 'sans-serif'],
        sans: ['"Plus Jakarta Sans"', '"Inter"', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'Menlo', 'monospace'],
      },
    },
  },
  plugins: [],
}
