# A Life Unwritten — project summary

## One sentence

**A Life Unwritten** is an original, portrait-first 2D life simulator where the player starts at age 18 and builds a believable adult life one week at a time through work, study, money decisions, relationships, travel, possessions, business risk, and difficult consequences.

It is inspired by the readability of decision-based life games, but it does not copy another game's branding, writing, interface, or assets. The city is a connected set of districts and opportunities rather than a large 3D world.

## What the player does

The player creates a person, chooses a first home, applies for work, and uses a limited weekly time budget. Each **Next Week** action advances exactly seven days. The simulation then processes scheduled payroll, taxes, rent, utilities, transportation, debt, business operations, relationships, assets, markets, events, and wellbeing.

The player is not required to become rich. A successful life can mean:

- building a stable career;
- studying for a better opportunity;
- recovering from debt or unemployment;
- running a small business;
- collecting art or buying a home;
- building friendships, romance, and family connections;
- moving to a city that fits a different lifestyle;
- taking calculated investment risk;
- surviving crime, court, jail, or a difficult financial period and rebuilding.

Every money change has a reason in the ledger, and every major system can create both opportunity and cost.

## Current product identity

- **Genre:** menu-driven life simulation / personal-economy strategy.
- **Format:** single-player, offline, 2D, portrait-first, resizable desktop UI.
- **Engine:** Godot 4.6.1 or newer, GDScript only.
- **Core unit of time:** one week.
- **Starting age:** 18.
- **Currency:** fictional game dollars stored as integer units.
- **Tone:** grounded, humane, occasionally funny, never a guaranteed power fantasy.
- **Visual language:** quiet editorial mobile banking/lifestyle app; warm paper surfaces, dark ink typography, restrained color accents, readable cards, real catalog thumbnails, and touch-sized controls.

## Main navigation

The five bottom navigation pages are always available during the life simulation:

1. **LIFE** — portrait, age/date, current situation, wellbeing, history, upcoming obligations, active activities, and the Next Week action.
2. **CITY** — current city, five districts, locations, services, commute, travel quotes, and relocation.
3. **OCCUPATION** — current job, job applications, pay preview, education, skills, hobbies, freelance gigs, and the player marketplace.
4. **ASSETS** — owned collection, securities and crypto trading, physical market, banking, transaction history, vehicles, art, homes, and useful equipment.
5. **PEOPLE** — persistent family, friends, partners, coworkers, rivals, portraits, relationship history, and actions.

The Next Week dock is fixed above the navigation. It shows available weekly hours and is the single primary progression action.

## Current playable loop

1. Choose **New life**.
2. Enter a name, pronouns, portrait, background, and starting trait.
3. Choose one of three starting homes.
4. Browse the city and occupation pages.
5. Apply for one of five starting jobs or enroll in the training course.
6. Spend the limited weekly hours on work, study, people, hobbies, gigs, or city actions.
7. Review upcoming obligations.
8. Tap **Next Week** once.
9. Read the income/expense/event summary.
10. Continue, save manually, or return later through autosave and backup recovery.

## Content currently in the build

- Original character identity with eight illustrated portrait choices.
- Seven persistent people with stable IDs and remembered relationship history.
- Five usable city districts: Downtown, Commercial, Industrial, Residential, and Government.
- Six fictional cities with different rent, utility, tax, salary, transit, and job-market profiles.
- Five starting jobs with requirements, schedules, performance, promotion, resignation, and dismissal behavior.
- One workplace certificate course with a three-week commitment.
- Five hobbies and six skill-gated freelance briefs.
- One small business, Street Bowl Kitchen, with demand, pricing, staff, capacity, marketing, maintenance, breakdowns, expansion, and failure risk.
- Eight fictional stocks, four crypto instruments including Bitcoin, Solana, Ethereum, and Dogecoin, two funds, and a bond.
- Fractional crypto quantities, fee-inclusive order previews, FIFO lots, realized/unrealized profit, price history, news, and independent seeded price movement.
- Physical market categories for cars, homes, art/collectibles, and gear.
- Realistic vehicle finance, insurance, fuel, maintenance, depreciation, reliability, breakdowns, negative equity, and repossession rules.
- Six-city travel and relocation with fares, movers, security deposit, first rent, old-deposit credit, local transport, and commute costs.
- Forty data-driven events with positive, ordinary, negative, difficult, delayed, crime, court, jail, work, housing, finance, and relationship outcomes.
- Integer-currency ledger, biweekly paychecks, itemized taxes, monthly scheduled bills, debt recovery, save/load, autosave, and one backup.
- Real catalog photos for notable cars, crypto, stocks, bonds, and homes, with credits in `assets/photography/ATTRIBUTION.md`.

## What makes it different

The game treats a life as a connected set of tradeoffs instead of a sequence of jackpot buttons:

- A higher salary can come with a longer commute and more taxes.
- A car can unlock work but creates insurance, fuel, loan, and maintenance obligations.
- A relationship action consumes time and money but can later unlock help, work, or conflict.
- A business can grow, but staffing, pricing, demand, maintenance, and cash reserves matter.
- A market price moves independently of the player's purchase.
- A crime choice can succeed, create suspicion, or return later through investigation and court.
- A move changes both opportunity and the cost of ordinary life.

## Important boundaries

- All companies, markets, coins, prices, news, jobs, cities, and transactions are part of the fictional simulation.
- Real-name crypto and art references are visual or thematic references only; there are no wallets, exchanges, payments, or real investment advice.
- Museum works appear as collectible editions/reproductions. The player never owns the Mona Lisa or another museum original.
- Crime and hacking are abstract fictional decisions. The game does not provide real-world attack instructions.
- Mining, deeper family simulation, richer vehicle customization, and optional mini-games are planned expansion areas, not required for the first milestone.

## Who this is for

The intended player likes:

- reading short, consequential choices;
- seeing money and time explained clearly;
- trying different life paths without a single correct build;
- comparing risk and stability;
- collecting visible possessions;
- returning to a save and seeing delayed consequences unfold.

## Current release

The current public Xogot package is **v0.4.0**, built from the `main` branch and verified with Godot 4.6.1. See [XOGOT.md](XOGOT.md) for mobile setup and [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) for the test and limitation summary.
