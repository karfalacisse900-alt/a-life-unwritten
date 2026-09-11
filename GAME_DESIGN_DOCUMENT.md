# A Life Unwritten — game design document

## 1. Product vision

Build a believable, readable life simulator in which the player can make a life that feels like theirs. The game should make ordinary systems interesting: a paycheck, an overdue bill, a commute, a conversation, a cheap room, a used car, a training course, a risky trade, or a move across the country.

The design goal is not maximum feature count. It is **connected consequence**: decisions should affect at least one other part of the player's life, and the player should be able to understand why the result happened.

## 2. Design pillars

### Agency without a single best path

The game should support stable employment, education, business, investment, relationships, creative work, crime/recovery, and relocation. A modest, safe path and a risky, ambitious path must both be playable.

### Clear money and time

The player always knows the cash balance, savings, debt, next paycheck, upcoming bills, weekly hours, known action costs, and the reason a transaction happened. Uncertain outcomes are labeled as uncertain instead of pretending to be guaranteed.

### The city as opportunity, not walking simulation

The city is represented by district directories, services, travel, commute, housing, and opportunity cards. There is no large 3D city to slow the game down or distract from the life decisions.

### People remember

Persistent people have stable IDs, attributes, closeness, trust, chemistry, tension, cooldowns, and history. A person can help, recommend, argue, become a partner, become a rival, or return in a later event.

### Every system has a cost

Income, a business, an investment, a car, a home, mining equipment, and relationships all consume money, time, attention, or risk capacity. No button may generate unlimited guaranteed profit.

### Mobile-first readability

The app is designed around a 540×960 logical portrait canvas and remains usable at phone and desktop sizes. Controls are touch-friendly, pages scroll vertically, the bottom navigation remains stable, and each screen has one clear primary action hierarchy.

## 3. Player journey

### Opening

The player sees a quiet, editorial welcome screen and chooses a new life or continue. Character creation asks only for decisions that matter immediately: name, pronouns, portrait, background, and one trait.

### First week

The player chooses housing, sees deposit and recurring costs, then uses CITY and OCCUPATION to find work or study. The player starts with limited cash, so the first decision is about stability and affordability rather than cosmetic power.

### First month

The player experiments with time: work, a hobby, a relationship, a course, a gig, or a city service. The first biweekly paycheck and monthly bills teach the schedule. The ledger makes the economy legible.

### First turning point

An event, job result, relationship development, or money shortage forces a choice. The player may apply for better work, train, start a venture, sell an asset, ask a person for help, move, or recover from a setback.

### Long-term play

The player creates a personal story through possessions, career, relationships, places lived, investments, business decisions, crimes and consequences, and the history panel. There is no final score required to consider a run successful.

## 4. Weekly simulation

The Next Week button is the primary game action.

Before advancing, LIFE shows:

- current date and age;
- hours remaining;
- next paycheck preview;
- known monthly or weekly obligations;
- active course, gig, business, travel, or legal commitments;
- critical warnings such as arrears, expiring insurance, or an upcoming payment.

On one valid press, the controller advances one calendar week exactly once. Processing order is:

1. Advance the calendar by seven days.
2. Resolve due delayed event effects.
3. Process employment schedule and performance.
4. Process base housing obligations.
5. Process payroll on the correct biweekly week and itemize taxes.
6. Process city taxes, commute costs, and local transport.
7. Process relationships and cooldowns.
8. Process hobbies, courses, gigs, crafting, and marketplace demand.
9. Process vehicles, physical assets, upkeep, and breakdowns.
10. Move the independent fictional market and process distributions/news.
11. Apply wellbeing changes and select an eligible life event.
12. Build a readable summary and autosave.

The controller is idempotent for the current `week_index`. Repeated input cannot pay the same paycheck or bill twice.

## 5. Character model

Creation fields:

- name;
- pronouns;
- original portrait selection;
- background;
- one starting trait.

Tracked state:

- cash, savings, debt;
- health, happiness, stress, energy, reputation;
- skills and education;
- employment and performance;
- housing and city;
- relationships;
- business;
- securities, crypto, physical assets, and vehicle;
- criminal record and ongoing legal state;
- event history, cooldowns, delayed effects, and weekly summary.

Backgrounds are tradeoffs rather than direct upgrades. For example, a fresh start can provide flexibility but less cash; a family-supported start can reduce housing pressure but create relationship expectations; a practical background can add skill while limiting early free time.

## 6. Navigation and screen behavior

### LIFE

The Life page is the home screen after creation. It prioritizes the portrait and current chapter, then shows wellbeing, money, housing, occupation, event history, active commitments, upcoming costs, and the Next Week dock.

### CITY

Local mode shows the current city, cost-of-living metrics, district directory, current commute, and available transport. Travel mode compares visits. Move mode shows relocation quotes and requirements.

Districts:

- **Downtown:** bank, corporate offices, crypto office, premium apartments, restaurants.
- **Commercial:** retail, barber, jewelry, dealership, small-business opportunities.
- **Industrial:** warehouses, mining facilities, delivery work, garages, cheaper commercial space.
- **Residential:** apartments, houses, parks, neighborhood activities.
- **Government:** police, courthouse, jail, public services.

### OCCUPATION

Career shows current work and open roles. Study shows qualifications and course commitments. Pursuits shows hobbies, freelance briefs, crafting, inventory, and listing. Market shows independent work and player-made items.

### ASSETS

Owned shows collection and net worth. Trade shows securities and crypto. Shop shows vehicles, homes, art, and gear. Money shows cash, savings, debt, bills, and the ledger. Asset cards use real thumbnails when available and a code-drawn fallback when not.

### PEOPLE

The list uses portraits, names, role, closeness, and a short status. Opening a person reveals history and available actions such as spend time, ask for help, gift, argue, date, break up, or make a business proposal.

## 7. Employment and education

Starting job examples:

- warehouse worker;
- retail assistant;
- delivery worker;
- security guard;
- office assistant.

Each job has pay, requirements, schedule hours, district, performance, and a possible path to promotion or dismissal. Applications consume time and can fail for understandable reasons such as skills, health, reputation, record, or circumstance.

Pay is biweekly in normal gameplay. Gross pay, federal/state/payroll/local withholding, and estimated take-home are shown before the player commits to long-term choices.

The first training course is a workplace certificate. It has an enrollment cost, enrollment time, weekly hours, weeks remaining, skill effects, and eligibility conditions.

## 8. Economy and finance

### Money rules

- Internal currency is integer dollars.
- Every change is recorded in `state.ledger`.
- Positive entries are income; negative entries are expenses.
- Recurring bills use explicit schedules.
- Rent and utilities do not silently charge every week unless their schedule says so.
- Overdue obligations create readable consequences rather than invisible penalties.

### Living costs

The economy can include rent, utilities, phone, groceries, healthcare, transportation, insurance, loan payments, local taxes, fuel, maintenance, and business expenses.

### Housing

Early options include living with family, renting a room, and renting an apartment. Housing affects monthly cost, wellbeing, space, commute, mining/equipment eligibility, and relocation requirements.

### Banking

The Money page supports cash, savings, debt repayment, transaction history, and upcoming obligations. Deposits and withdrawals are explicit actions with known amounts.

## 9. Securities and crypto

The game includes fictional market infrastructure and a few real-name reference instruments. Real money never enters the game.

The market supports:

- stocks, funds, bonds, and crypto;
- buying and selling;
- fractional crypto quantities;
- quantity input rather than one-unit-only buttons;
- maximum-order helper;
- trading fees;
- average/FIFO cost basis;
- realized and unrealized gains;
- independent seeded price movement;
- price history and market news;
- order limits and insufficient-cash handling.

Prices must not rise automatically because the player bought. The market is simulated independently before the player's portfolio is valued.

Visual assets include credited Bitcoin, Solana, Ethereum, stock-floor, and bond-certificate thumbnails. They are recognition aids, not live market feeds.

## 10. Physical assets

The physical marketplace includes:

- vehicles;
- homes/property;
- art and collectible editions;
- equipment and useful belongings.

Physical items have a stable ID, purchase/cost basis, current value, condition, upkeep, and category-specific behavior. Art cards use museum/public-domain image references for editions; the game never claims to transfer a museum original.

Vehicles have purchase price, down payment, APR, term, payment, insurance, fuel, maintenance, reliability, depreciation, practical access tags, breakdown risk, negative equity, and possible repossession. The current catalog uses real photos for everyday cars, EVs, SUVs, vans, sports cars, and Bugattis with attribution.

## 11. Business and independent work

Street Bowl Kitchen is the first complete business. It tracks:

- startup cost;
- revenue and operating expenses;
- demand and reputation;
- price choice;
- staff and capacity;
- marketing;
- maintenance and breakdown risk;
- expansion and failure risk;
- weekly profit/loss.

Independent work adds hobbies, freelance briefs, crafting, inventory, player marketplace listings, uncertain demand, review delay, and time/cash limits.

## 12. Relationships

People are persistent simulation entities, not disposable buttons. Each relationship can track:

- stable person ID;
- name, portrait, role, and district;
- closeness, trust, chemistry, tension, and status;
- action costs and time requirements;
- cooldowns;
- remembered history;
- future recommendations, help, conflict, romance, partnership, or event eligibility.

Relationship actions are processed by `RelationshipSystem`, never by UI drawing code.

## 13. Crime, police, court, and jail

Crime is fictional and abstract. Choices can create suspicion, investigations, arrest, fines, court outcomes, jail time, criminal records, relationship damage, and reduced job access. Success does not mean consequence-free play, and arrest is not guaranteed every time.

While in jail, the weekly loop still advances. Available activities, costs, relationships, events, and opportunities change with the legal state. Hacking and robbery remain invented decision scenarios; no real attack instructions are provided.

## 14. Event system

Events are data-driven and validated. Each event has:

- stable ID;
- eligibility conditions;
- event text;
- choices;
- known costs;
- immediate effects;
- delayed effects;
- cooldown or repeat restriction.

The catalog includes ordinary life events as well as positive, negative, and difficult choices. The system prevents nonsensical outcomes such as a promotion while unemployed or a mining repair bill without equipment.

## 15. Visual and interaction specification

The UI is code-native rather than a static mockup. It uses:

- 540×960 logical portrait layout;
- warm paper background;
- dark ink and muted gray text;
- teal, blue, purple, orange, green, red, and gold semantic accents;
- DM Sans body typography;
- Libre Baskerville display headings;
- one-pixel rules and measured card padding;
- scrollable page content with fixed header/navigation/dock;
- minimum touch targets without inflating the visual design;
- one clear primary action per card;
- real thumbnails with a lightweight fallback drawing.

Avoid:

- button grids with no hierarchy;
- fake 3D city scenes;
- unreadable microtext;
- hidden costs;
- unbounded action spam;
- uncredited third-party assets;
- placeholder buttons that imply unimplemented features.

## 16. Save and compatibility rules

Saves are versioned. Normal save behavior includes manual save, autosave, one backup, graceful handling of missing/corrupt primary data, and round-tripping of extension state in `flags`.

Stable IDs are used for jobs, events, people, cities, assets, vehicles, properties, and actions. Display names may change without breaking a save.

## 17. Expansion roadmap

### Next useful additions

- richer home interiors as small asset cards rather than a 3D city;
- more occupations and promotion ladders;
- deeper family/children state;
- more art, vehicles, and property variants;
- better event authoring tools and debug inspection;
- an optional short invented puzzle for selected crime scenarios;
- more accessible text-size and contrast settings.

### Later systems

- mining equipment with electricity, capacity, maintenance, space, and breakdowns;
- expanded businesses and partnerships;
- vehicle customization for clothing, hairstyle, and portrait presentation;
- deeper jail programs and reentry paths;
- long-run legacy, estate, and end-of-life systems.

## 18. Success criteria

A build is ready for a milestone when:

- a new character can reach the first paycheck;
- the same week cannot process twice;
- recurring costs follow their schedule;
- every money change appears in the ledger;
- job, course, relationship, asset, travel, and event eligibility are explainable;
- a save can be loaded without losing simulation state;
- the interface remains readable at portrait phone and desktop sizes;
- the game remains interesting when the player is broke, unemployed, in debt, or recovering.
