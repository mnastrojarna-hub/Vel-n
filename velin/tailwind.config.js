/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        brand: {
          green: '#74FB71',
          dark: '#1a2e22',
          bg: '#dff0ec',
          bg2: '#cde8e2',
          black: '#0f1a14',
          gd: '#3dba3a',
          gdk: '#1a8a18',
          gp: '#e8ffe8',
          g100: '#f1faf7',
          g200: '#d4e8e0',
          g400: '#8aab99',
          g600: '#4a6357',
        },
      },
      fontFamily: {
        montserrat: ['Montserrat', 'Segoe UI', 'sans-serif'],
      },
      borderRadius: {
        card: '18px',
        btn: '50px',
      },
      boxShadow: {
        card: '0 4px 20px rgba(15,26,20,.1)',
      },
    },
  },
  plugins: [],
}
