# Team Roles Board

Team board with Tasks, Late rule, Accounts, Entry records and an admin-only Team tab.
Live at https://landed-tasks-app.vercel.app/ (deployed by Vercel from this repo).

- `index.html` – the board (plain HTML + supabase-js, no build step)
- `config.js` – Supabase project URL and anon key
- `supabase/setup.sql` – tables, security rules, automatic entry records and the data carried over from the old claude.ai board
- `SETUP.md` – one-time setup steps and how to reset a password

Each person logs in with their own username and password. The database records every log-in and every
change with who and when, and those records can't be edited from the board.
