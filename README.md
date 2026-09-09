# A Life Unwritten

An original, menu-driven 2D life simulation built in GDScript for Godot 4.6.1 or newer. Its portrait-first interface is drawn entirely in code with a production-style design system: measured spacing, neutral surfaces, one-pixel borders, clear typography, compact financial tables, touch-sized controls, and deterministic portrait identities. The live interface uses a small set of clearly attributed public-domain artwork thumbnails and original code-drawn item illustrations.

## Start playing

Double-click `PLAY_GAME.bat`. The project uses the regular (non-.NET) portable Godot build at:

`C:\dev\Godot-4.7.2-standard\Godot_v4.7.2-stable_win64.exe` (or Godot 4.6.1+)

To inspect or edit the project, double-click `OPEN_EDITOR.bat`. You can also import `project.godot` in Godot 4.7.2 or a compatible Godot 4 release.

## First playable milestone

- Create an age-18 character with a name, pronouns, a configurable original profile identity, a background tradeoff, and a trait.
- Choose among three homes with deposits, moving costs, utilities, rent, wellbeing effects, and space rules.
- Navigate LIFE, CITY, OCCUPATION, ASSETS, and PEOPLE through a portrait-mobile interface that also resizes on desktop. A persistent Next Week button keeps the core loop one tap away.
- Visit five connected city districts and their usable locations; later expansion locations are explicitly disabled.
- Apply to five jobs, work scheduled hours, improve performance, earn promotions, resign, or be dismissed. Salaries adjust to the local city and pay on a biweekly schedule.
- Complete a three-week workplace certificate that unlocks opportunities.
- Use OCCUPATION for education, employment, five restorative hobbies, six skill-gated freelance briefs, and a neighborhood marketplace. Craft five different products, list finished inventory, and let uncertain demand resolve on future weeks.
- Use ASSETS for a full simulated brokerage with eight fictional stocks, four fictional cryptocurrencies, two exchange-traded funds, and a bond. It tracks fractional crypto units, fees, FIFO cost basis, price history, realized and unrealized gains, allocations, distributions, weekly order limits, and independent seeded market movement.
- Buy property, original art, collectibles, and useful work equipment. Physical possessions wear, appreciate or depreciate, and post their upkeep to the same ledger.
- Buy or finance one of six realistically priced vehicles. Registration, down payment, APR, loan term, monthly payment, insurance, fuel, maintenance, reliability, breakdowns, depreciation, negative equity, and repossession are simulated and itemized.
- Visit or relocate among six fictional cities with different salary, rent, utility, local-tax, job-market, and transit profiles. Trips consume fare and time; moves include one-way travel, movers, a security deposit, first rent, old-deposit credit, and local transport setup.
- Operate Street Bowl Kitchen with pricing, staffing, demand, capacity, marketing, maintenance, breakdown, expansion, and failure risk.
- Maintain seven persistent relationships with time, cost, trust, closeness, chemistry, tension, cooldowns, and remembered history.
- Resolve 40 data-driven events, including delayed consequences, debt recovery, abstract crime, court, jail, reentry, work, housing, and relationships.
- Advance exactly one week at a time. Paychecks arrive biweekly; rent, utilities, phone, groceries, healthcare, transport passes, insurance, loan payments, and other recurring costs follow explicit schedules instead of being charged every week.
- Review a reasoned integer-currency ledger and a post-week cash summary.
- Save manually with `Ctrl+S` or the LIFE-page Save button. The game also autosaves, keeps a backup, and can recover from a damaged primary save.

The interface is code-drawn and uses only original project resources; no outside game branding or assets are copied. All stocks, companies, coins, prices, news, and trading stay inside the simulation. There are no real wallets, payments, exchanges, securities, or mining integrations. Deeper mining remains a later expansion.

## Controls

- Mouse/touch: activate buttons and swipe/scroll long pages.
- `Esc`: close a detail view or message.
- `Ctrl+S`: manual save.

## Architecture and tests

Simulation code is separated under `scripts/systems`, shared state is in `scripts/core`, page renderers are in `scripts/ui/pages`, and validated reusable content is in `data`.

Run the automated suites from PowerShell:

```powershell
& 'C:\dev\Godot-4.7.2-standard\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\dev\a-life-unwritten' --script res://tests/core_test.gd
& 'C:\dev\Godot-4.7.2-standard\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\dev\a-life-unwritten' --script res://tests/work_test.gd
& 'C:\dev\Godot-4.7.2-standard\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\dev\a-life-unwritten' --script res://tests/events_test.gd
& 'C:\dev\Godot-4.7.2-standard\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\dev\a-life-unwritten' --script res://tests/activity_test.gd
& 'C:\dev\Godot-4.7.2-standard\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\dev\a-life-unwritten' --script res://tests/assets_test.gd
& 'C:\dev\Godot-4.7.2-standard\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\dev\a-life-unwritten' --script res://tests/milestone_test.gd
& 'C:\dev\Godot-4.7.2-standard\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\dev\a-life-unwritten' --script res://tests/controller_flow_test.gd
& 'C:\dev\Godot-4.7.2-standard\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\dev\a-life-unwritten' --script res://tests/realistic_economy_test.gd
& 'C:\dev\Godot-4.7.2-standard\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\dev\a-life-unwritten' --script res://tests/market_system_test.gd
& 'C:\dev\Godot-4.7.2-standard\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\dev\a-life-unwritten' --script res://tests/travel_system_test.gd
& 'C:\dev\Godot-4.7.2-standard\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\dev\a-life-unwritten' --script res://tests/real_life_integration_test.gd
```
