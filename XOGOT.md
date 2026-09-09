# Play in Xogot on iPad or iPhone

This is a standard Godot GDScript project. It does not require .NET, Windows,
real trading accounts, or an exported iOS app. Use the current Xogot release.
Xogot 1.6 is based on Godot 4.6.1; this project targets that engine version or newer.

1. From this GitHub repository, either download the attached Xogot ZIP from the
   Releases section, or tap **Code > Download ZIP** for the source project. Save
   that ZIP to iCloud Drive or your device's Files app.
2. In Files, tap the ZIP once to unzip it. The source download creates an
   `a-life-unwritten-main` folder; the release ZIP creates an `A Life Unwritten`
   folder. Use the folder containing `project.godot`, `main.tscn`, `assets`,
   `data`, and `scripts`.
3. Copy that whole project folder to **On My iPad > Xogot** (or
   **On My iPhone > Xogot**). Keep the folder structure intact.
4. Open Xogot, find the project in its project manager, and open it. Restart
   Xogot if the copied folder has not appeared yet. Let first-time asset import finish.
5. Tap **Play** at the top. Choose **New life**, enter a name, choose a portrait,
   background and trait, then choose your housing.

Do not tap the Windows `.bat` launchers on an iPad. They are only for the PC copy.
If Xogot asks to change the renderer, choose **Mobile**. The project also specifies
the Mobile renderer for mobile devices automatically.

## Touch controls

- Tap navigation at the bottom; swipe lists vertically.
- Tap a character-name field or the quantity field in an investment order to
  open the device keyboard. Close the keyboard before using controls it covers.
- ASSETS > Market > Crypto > Buy opens a quantity ticket. Enter a decimal coin
  amount, read the total including fees, and confirm. Opening a ticket spends nothing.
- Read Coming up on LIFE before tapping Next Week. One tap advances one week;
  a summary explains the income, expenses, and events before you continue.
- Save from LIFE. Autosaves and a backup are stored in the app's project user-data
  area, not beside `project.godot`. Copying source alone does not transfer a PC save.

## What the assets represent

Bitcoin, Solana and other real-name instruments are simulated game assets.
Quotes, fees, news and returns are not live market data. Vehicles use illustrative
game prices and costs, not dealer quotations. Famous art is sold as collectible
editions/reproductions, not ownership of museum originals. Appraisals can fall.

## Device checks

The project is tested with desktop Godot, including the Godot 4.6.1 version used
by Xogot 1.6. Actual iPad/iPhone execution still needs testing on your device.
Check portrait selection, touch scrolling, the decimal keyboard, and a save/load.
If a device-specific error occurs, send the first red error from Xogot's output.

Official import instructions: https://docs.xogot.com/documentation/xogot/getting-started/
Engine version: https://blog.xogot.com/xogot-1-6-powered-by-godot-4-6-with-new-videos-tutorials-and-starter-kits/
