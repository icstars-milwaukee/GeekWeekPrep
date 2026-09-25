# GeekWeekPrep

Setup files for GeekWeekPrep. Follow the two steps below **in order**.

> **Heads up:** everything in this repo is **prep material**. The official
> Geek Week guidelines and rules arrive by **email** — watch your inbox
> and read them carefully when they land.

## Step 1 — Unlock SQL Server permissions (one time)

If you get **"CREATE DATABASE permission denied"** errors in SQL Server
Management Studio, your Windows account isn't trusted by SQL Server yet.
This fixes that on your own laptop.

**Easiest way — copy, paste, done:**

1. Click **Start**, type `powershell`, and open **Windows PowerShell**
   (no need for admin — the script asks for it itself).
2. Copy this whole line, paste it into the blue window, and press Enter:

```powershell
irm https://raw.githubusercontent.com/icstars-milwaukee/GeekWeekPrep/main/Unlock-SqlPermissions.ps1 -OutFile "$env:TEMP\Unlock-SqlPermissions.ps1"; powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\Unlock-SqlPermissions.ps1"
```

3. When the blue *"Do you want to allow this app to make changes?"* box
   appears, click **Yes**.
4. Wait for the green **SUCCESS!** message, then press Enter to close.

> The script briefly restarts your local SQL Server so it can add your
> account as an administrator, then starts it back up. It only affects
> the SQL Server on **your** laptop.

## Step 2 — Load the practice database

1. Download [`GeekWeekData.sql`](./GeekWeekData.sql) (click the file,
   then the **Download raw file** button).
2. Open it in SQL Server Management Studio (connect to `.\SQLEXPRESS`
   with Windows Authentication).
3. Click **Execute**. It should complete with no permission errors.

**Prove it worked:** in SSMS, open a New Query and run

```sql
USE Northwind;
SELECT COUNT(*) FROM Orders;
```

The answer should be **830**.

## Workshop deck (facilitators)

[`REF-geekweekprep-workshop-deck.html`](./REF-geekweekprep-workshop-deck.html)
— the GeekWeekPrep session slides. Download and open in a browser: arrow keys
or tap the screen edges to navigate, **Ctrl+P → Save as PDF** exports one
slide per page.

## Geek Week do's and don'ts

[`REF-geekweek-dos-and-donts.md`](./REF-geekweek-dos-and-donts.md) — how
testing works during Geek Week and what's expected of you. Read it before
Monday.

## Optional challenge

[`DEL-0928-product-catalog.md`](./DEL-0928-product-catalog.md) — after the
workshop, rebuild the product catalog query from a blank query window, by
hand, and bring it to Geek Week Monday. Optional, but the reps count.

## Having trouble?

Take a screenshot of the error and show it to Carl or Jakwoun.
