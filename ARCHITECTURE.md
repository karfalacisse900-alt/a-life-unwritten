# First Playable Architecture Contract

Godot target: 4.7.2, GDScript only. Currency is stored as integer dollars.

## Shared state

All systems receive one `LifeGameState` instance from `scripts/core/LifeGameState.gd`.

Required public fields:

- `created: bool`, `player_name: String`, `pronouns: String`, `appearance: int`, `background_id: String`, `traits: Array[String]`
- `birth_year: int`, `age: int`, `calendar: Dictionary` (`year`, `month`, `day`, `week`, `week_index`)
- `cash: int`, `savings: int`, `debt: int`, `ledger: Array[Dictionary]`
- `health`, `happiness`, `stress`, `reputation`, `energy`, `weekly_time`, all integers
- `skills: Dictionary`, `education: Array[String]`
- `employment: Dictionary` (`job_id`, `title`, `weekly_pay`, `performance`, `weeks`)
- `housing_id: String`, `owned_properties: Array[String]`
- `relationships: Array[Dictionary]`
- `business: Dictionary`
- `crypto: Dictionary`
- `crime: Dictionary`
- `active_activities: Array[Dictionary]`, `delayed_effects: Array[Dictionary]`
- `event_history: Array[String]`, `cooldowns: Dictionary`, `flags: Dictionary`
- `last_week_summary: Array[String]`
- `seed: int`, `rng_state: int`

Required methods: `reset_new_game()`, `to_dict()`, `from_dict(data)`, `randf_seeded()`, `randi_seeded(max_value)`, `add_history(text)`, `spend_time(hours, reason) -> bool`.

## System APIs

- `EconomySystem.record(state, amount, reason, category)` changes cash and records ledger entry. Positive is income, negative is expense.
- `EconomySystem.process_week(state, content) -> Array[String]` handles biweekly gross payroll and itemized withholding, monthly scheduled living costs, overdue obligations, debt, business, and vehicle finance. Legacy weekly payroll remains readable for old isolated tests, while normal gameplay explicitly enables realistic finances.
- `CalendarSystem.advance_one_week(state) -> Dictionary` advances exactly seven days and returns boundary information including `new_month`.
- `EmploymentSystem.get_jobs()`, `eligible(state, job)`, `apply(state, job_id) -> String`, `resign(state) -> String`, `process_week(state) -> Array[String]`.
- `HousingSystem.get_options()`, `move_to(state, housing_id, economy) -> String`, `current(state)`.
- `BusinessSystem.start(state, economy)`, `set_decision(state, key, value)`, `process_week(state, economy) -> Array[String]`.
- `RelationshipSystem.seed_people(state)`, `act(state, person_id, action_id, economy) -> String`, `process_week(state) -> Array[String]`.
- `EventSystem.load_content()`, `select_event(state)`, `resolve(state, event_id, choice_id, economy) -> Dictionary`, `process_delayed(state, economy) -> Array[String]`.
- `ActivitySystem.get_hobbies()`, `get_gigs()`, `get_marketplace_items()`, `perform_hobby(...)`, `accept_gig(...)`, `craft_item(...)`, `list_item(...)`, and `process_week(...)` power OCCUPATION pursuits without putting rules in the renderer.
- `AssetSystem.get_categories()`, `get_market_list(...)`, `get_owned(...)`, `buy(...)`, `sell(...)`, `maintain(...)`, `net_worth(...)`, and `process_week(...)` power ASSETS. Its market advances independently of player purchases and all cash effects use the shared ledger.
- `MarketSystem.get_market_list(...)`, `get_holdings(...)`, `get_portfolio_summary(...)`, `buy(...)`, `sell(...)`, and `process_week(...)` provide cent-precise fictional securities and crypto trading, FIFO lots, P&L, histories, news, fees, and seeded price movement that is independent of player trades.
- `VehicleFinanceSystem` owns one realistic vehicle contract at a time. It quotes cash and financed purchases and processes registration, APR-based loans, insurance, personal/commute fuel, maintenance, depreciation, breakdowns, arrears, sale payoff, and repossession.
- `TravelSystem` owns the current city, intercity visits, relocation quotes, city housing contracts, selected commute, local taxes, city rent/utility deltas, fares, parking, and commute time. It runs after Economy so city tax is based on an actual paycheck ledger entry.
- `SaveSystem.save_game(state)`, `load_game(state)`, `has_save()`, with version 2, autosave, one backup, and graceful failure.

Content lives under `data/` as JSON with stable IDs. Market, vehicle, travel, asset, finance, and occupation extension state is kept inside the serialized `flags` dictionary, so version-2 saves round-trip it without UI ownership. UI code only renders contexts and emits stable actions; it does not own simulation rules.

Weekly controller order is deliberate: calendar → delayed events → employment → base housing → economy/payroll → city tax and commute → relationships → activities → physical assets → simulated markets → wellbeing. Every processor is idempotent for the current `week_index`.
