# Setting up logins for the Team Roles Board

The board at https://landed-tasks-app.vercel.app/ uses Supabase for usernames, passwords and data.
Do these steps once. They take about 10 minutes.

## 1. Create the Supabase project

1. Go to https://supabase.com, sign up (free) and click **New project**.
2. Name it `landed-tasks`, set a database password (keep it somewhere safe), pick the **Singapore** region, and create it.

## 2. Turn off public sign-ups

In the project: **Authentication → Sign In / Providers**.

- Turn **off** "Allow new users to sign up".
- Under **Email**, turn **off** "Confirm email".

Only you will create logins.

## 3. Create the team's logins

**Authentication → Users → Add user → Create new user**, once per person:

| Field | What to enter |
|---|---|
| Email | `username@landed-tasks.app`, for example `jonathan@landed-tasks.app` |
| Password | a starting password for that person |
| Auto Confirm User | ticked |

Create at least yours, with the username `jonathan`. That account becomes the admin.
The others can be added now (`rachael`, `jordon`, `yc`, ...) or later.
No email is ever sent to these addresses. They only turn a username into a login.

## 4. Build the database

**SQL Editor → New query**. Paste the whole of [`supabase/setup.sql`](supabase/setup.sql) and click **Run**.

This creates the tables, the security rules and the automatic entry records, and copies in the current
tasks, accounts entry, late rule, roles and old entry records.

## 5. Connect the website

**Project Settings → API**. Copy:

- **Project URL**
- **anon public** key (not the `service_role` key, which must never go on the website)

Send both to Claude, or paste them into [`config.js`](config.js) and push. Vercel updates by itself.

## Using it

- People log in with their **username** and password, and can use **Change password** at the top.
- **Entry records** shows every log-in, log-out, password change, add, edit and delete, with who and when.
  The database writes these records itself, so nobody can change or delete them from the board.
- Logins you add later start **switched off**. Switch them on in the board's **Team** tab, which only admins see.

## Resetting a forgotten password

In **SQL Editor**, run this with the person's username and a new temporary password:

```sql
update auth.users
set encrypted_password = crypt('NewTempPassword123', gen_salt('bf'))
where email = 'rachael@landed-tasks.app';
```

Then ask them to log in and use **Change password**.
