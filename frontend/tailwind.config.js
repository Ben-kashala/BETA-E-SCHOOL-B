/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'class',
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          50: '#f0f4ff',
          100: '#e0e9ff',
          200: '#c7d7fe',
          300: '#a4b8fc',
          400: '#818cf8',
          500: '#6366f1',
          600: '#4f46e5',
          700: '#4338ca',
          800: '#3730a3',
          900: '#312e81',
        },
        /* Charte E-School */
        eschool: {
          header: '#ededed',      /* fond entête / pied */
          'header-text': '#21335c',
          body: '#21335c',        /* fond corps */
          'body-text': '#ededed',
          avatar: '#ca9d1e',      /* fond avatar */
          'avatar-text': '#ededed',
        },
      },
    },
  },
  plugins: [],
}
