# A Life Unwritten — implementation status

Status: **first playable milestone complete; visual asset pass v0.4.0 published**

## Verified working

- Godot 4.6.1/Xogot-compatible project configuration.
- Character creation with name, pronouns, eight portraits, background, and trait.
- Three starting housing choices and housing setup flow.
- LIFE, CITY, OCCUPATION, ASSETS, and PEOPLE pages.
- Fixed Next Week dock with weekly hours and duplicate-input guard.
- Five city districts and six fictional cities.
- Five job listings, applications, schedules, performance, payroll, resignation, and dismissal paths.
- Biweekly paycheck preview and itemized taxes.
- Predictable monthly bills and arrears.
- Three-week training course.
- Hobbies, freelance work, crafting, inventory, listings, uncertain marketplace demand, and action limits.
- Street Bowl Kitchen business with meaningful operating choices and risk.
- Seven persistent relationships with action costs, cooldowns, and history.
- Eight fictional stocks, four crypto instruments, two funds, and a bond.
- Fractional crypto entry, MAX helper, fees, buy/sell quotes, FIFO cost basis, histories, P&L, news, and seeded independent market movement.
- Art and collectible editions with attributed real images.
- Vehicles with cash/finance quotes, loan, APR, payment, insurance, fuel, maintenance, reliability, depreciation, breakdown, sale, and repossession behavior.
- Travel, commute, intercity visits, relocation quotes, housing changes, and local cost profiles.
- Forty validated events, delayed effects, crime, court, jail, work, housing, finance, and relationship outcomes.
- Manual save, autosave, backup, versioned recovery, and save round-trip.
- Real catalog photography for vehicles, Bitcoin, Solana, Ethereum, stocks, bonds, and property. Full credits are in `assets/photography/ATTRIBUTION.md`.

## Deliberately limited or not yet implemented

- Mining is represented in content and eligibility rules, but a deeper equipment/profitability loop is still an expansion.
- There is no large 3D Roblox-style city; locations are menu-driven by design.
- There are no real wallets, exchanges, payments, live market feeds, or real-money transactions.
- The crypto and stock prices are fictional and seeded, not financial advice or live quotes.
- Art purchases are collectible editions/reproductions, not museum originals.
- Vehicle customization is not yet a full wardrobe/garage editor.
- Family and children systems are smaller than the relationship foundation and remain a future expansion.
- Optional crime mini-games are not required for the current playable loop.
- Actual iPhone/iPad runtime behavior still needs device-specific testing even though the project imports and renders through Godot 4.6.1.

## Test suites

The project contains automated tests for:

- core state, calendar, ledger, save recovery, and idempotence;
- employment and work flow;
- events, eligibility, delayed effects, crime, court, and jail;
- activities, freelance work, crafting, inventory, and limits;
- physical assets and catalog expansion;
- market movement, fractional orders, fees, holdings, and P&L;
- travel, relocation, housing, commute, tax, and city costs;
- realistic payroll, vehicle finance, insurance, fuel, maintenance, sale, and arrears;
- controller flow and all five pages;
- touch input, swipe cancellation, portrait selection, text input, and scrolling;
- real renderer UI screenshots at 540×960, 1000×800, and 390×844.

The full suite passes on the Godot 4.6.1 executable used for the Xogot release. A clean extracted v0.4.0 package was imported and passed `ui_render_test.gd` after first-time asset import.

## Release handoff

- GitHub repository: `https://github.com/karfalacisse900-alt/a-life-unwritten`
- Current release: `v0.4.0`
- Xogot package: `A-Life-Unwritten-Xogot-v5.zip`
- Engine tested: Godot 4.6.1 stable console/desktop build.
- Mobile guide: [XOGOT.md](XOGOT.md).

## Known practical constraints

The game is intentionally a single-player simulation with a local save. Its most important quality risks are content breadth, long-run balance, and device-specific touch behavior. When adding a system, add its state serialization and a focused regression test before increasing UI surface area.
