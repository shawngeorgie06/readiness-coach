# Readiness Coach web dashboard

Lightweight read-only view of the backend's Today API.

```bash
cp .env.example .env.local
npm install
npm run dev
```

Set `VITE_API_URL`, `VITE_API_TOKEN`, and `VITE_USER_ID` in `.env.local`. The backend must be running and configured with the same bearer token.
