# GeekWeek

Setup files for GeekWeek. Follow the two steps below **in order**.

## Step 1 — Unlock SQL Server permissions (one time)

If you get **"CREATE DATABASE permission denied"** errors in SQL Server
Management Studio, your Windows account isn't trusted by SQL Server yet.
This script fixes that on your own laptop.

1. Download [`Unlock-SqlPermissions.ps1`](./Unlock-SqlPermissions.ps1)
   (click the file, then the **Download** button).
2. Find the downloaded file, **right-click it → Run with PowerShell**.
3. When the blue *"Do you want to allow this app to make changes?"* box
   appears, click **Yes**.
4. Wait for the green **SUCCESS!** message, then press Enter to close.

> The script briefly restarts your local SQL Server Express so it can add
> your account as an administrator, then starts it back up. It only
> affects the SQL Server on **your** laptop.

If Windows blocks the download or the right-click option is missing, open
PowerShell in your Downloads folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Unlock-SqlPermissions.ps1
```

## Step 2 — Load the GeekWeek database

1. Download [`GeekWeekData.sql`](./GeekWeekData.sql).
2. Open it in SQL Server Management Studio (connect to `.\SQLEXPRESS`
   with Windows Authentication).
3. Click **Execute**. It should complete with no permission errors.

## Having trouble?

Take a screenshot of the error and show it to Carl or Jakwoun.
