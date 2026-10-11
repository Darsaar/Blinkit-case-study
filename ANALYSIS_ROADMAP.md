# Blinkit Case Study: Coimbatore Availability Analysis Roadmap

**Question:** Should the +20% indent increase on Milk and FnV for all Coimbatore stores go ahead? If not, what should happen instead?

**Data:** 8 weeks (6 Jul – 30 Aug 2026) of store × SKU × day data for Coimbatore (20 dark stores) and Salem (10 dark stores).

---

## Phase 1: Understand the problem

**Goal:** know exactly what you are testing.

The manager's message contains **4 testable claims**:

1. Coimbatore availability fell from 96% to 88%
2. The drop is in Milk **and** FnV
3. The cause is that stores are not ordering enough
4. +20% across all stores will fix it

- **Salem** is the control group (what "normal" looks like).
- One claim **cannot be tested**: "conversion dropped". There is no traffic or session data.

---

## Phase 2: Fix your definitions

**Goal:** the Readme asks you to define these and justify the choices.

| Metric | Definition | Reason |
|---|---|---|
| Availability | in-stock hours ÷ operating hours | Uses the Readme's own definition of in-stock time |
| Fill rate | received ÷ ordered, confirmed POs only | Measures the vendor on orders it accepted |
| Wastage | dumped ÷ (sold + dumped) | Comes from one table, so no join risk |
| Week | 7-day blocks starting Monday 6 July | Gives exactly 8 full weeks |
| Old stores, open days | Stores that existed before the period, open days only | Removes distortion from new stores and closures |

---

## Phase 3: Clean the data (every edge case handled once)

**Goal:** build clean versions of the tables so every later step is automatically correct. **Flag** problem rows rather than deleting them, so the raw picture can still be shown.

| # | Edge case | What's wrong | Decision |
|---|---|---|---|
| 1 | **Duplicate GRN rows** (827) | Received quantity is double-counted | Remove duplicates |
| 2 | **Maintenance closures**: CBE04 (11–16 Aug), CBE09 (15–19 Aug) | Recorded as 18 hours open with 0 in stock, so they look like stock-outs | Flag as closed and exclude from availability, demand and lost sales |
| 3 | **POs raised on closed days** (242, all cancelled) | Inflate cancellations and lower fill rate | Flag and exclude from fill rate |
| 4 | **New stores**: CBE16–CBE20, opened 3–6 Aug | Low starting availability drags down the city average | Flag and analyse separately |
| 5 | **Cancelled POs** (611 in total) | No receipt exists | Exclude from fill rate and state the choice |
| 6 | **Dumped while 0 hours in stock** (35 rows) | Looks odd, but plausible (stock expired, then ran out) | Keep and mention |
| 7 | **Sold + dumped > received** on some days | Stock carries over between days | Don't assume each day starts from zero |
| 8 | Duplicates, missing days, negative values, received > ordered | Checked; none found | Mention that you checked |
| 9 | **Date columns loaded as numbers** (epoch milliseconds, e.g. `1783296000000`) by some import tools | Date arithmetic fails: "Unimplemented type for cast (BIGINT -> DATE)" | Convert the date columns with `epoch_ms(...)::DATE` (optional Step 1b of `duckdb_01_setup_and_clean.sql`; only when dates show as numbers) |

**Output:** a clean daily table, a clean PO table and a clean GRN table, each with flags for *closed*, *new store* and *old store open*, plus a "data issues" note for the submission.

---

## Phase 4: Reproduce the headline

**Goal:** confirm you can see what the manager sees.

- Weekly availability by city using **all rows**, unfiltered.
- Coimbatore ≈ 96% in weeks 1–4, falling to 81% in week 6. Salem is flat at about 96%.
- Coimbatore's **row count jumps from week 5**: the set of stores being averaged changed.

---

## Phase 5: Remove the distortions (is the drop real?)

**Goal:** separate measurement noise from a real problem.

- Compare weekly availability three ways: **all stores**, **old store open**, **new stores only**.
- Measure the effect of closures alone: week 6 is about 83% with closed days and about 90% without.
- **Conclusion:** the real drop (old stores, open days) is about **96% → 90%** (about 6 points, not 8), and it starts **in week 6**. The rest comes from closures and new stores ramping up.

---

## Phase 6: Locate the problem

**Goal:** find *where* the real drop sits.

1. **By category:** Milk falls (~94% → ~79%). **FnV doesn't move** (~97%).
2. **By store:** every old store drops by about the same amount. CBE04 and CBE09 only look worse if closures are included.
3. **By SKU:** all 8 milk SKUs drop together.
4. **By day:** an overnight step change on **Monday 10 August**, not a gradual decline.
5. **Rule out closures as the cause:** stores that never closed drop on the same day. Reopened stores come back at normal levels, with no restocking dip and no dumping spike.

**Conclusion:** the drop is uniform across every store and every milk SKU, which points upstream to the supplier.

---

## Phase 7: Find the root cause (demand or supply?)

**Goal:** prove why milk ran out.

1. **Vendor mapping:** each city and category has one vendor. Coimbatore milk comes from **V03**, Coimbatore FnV from V11, Salem milk from V04 and Salem FnV from V12.
2. **Fill rate by vendor:** V03 falls from **~97% to ~71%** from 10 Aug. Every other vendor stays flat.
3. **Uniformity:** V03's drop is the same across every store and every SKU, including new stores.
4. **Percentage cut or capacity cap:** V03 delivers ~71% whatever the order size, and delivers *more* on high-demand days. It is not a capacity ceiling.
5. **Order → receive → sell funnel:** milk orders are normal, receipts fell, and almost everything received is sold. Stores are being **starved**. FnV is unchanged.
6. **Demand check:** milk sales per store-day **fell** because supply fell. Demand did not rise. (Divide by actual open store-days.)
7. **Wastage as a signal:** milk wastage *fell* (~1.4% → ~0.4%) at the same time, which confirms starvation.
8. **Salem as control:** different vendors, all stable. The problem is specific to V03.

**Conclusion:** the root cause is a **supply failure at V03**, not under-ordering.

---

## Phase 8: Test the manager's other claims

- **"Conversion dropped":** this cannot be measured with this data. Milk sales fell because milk wasn't on the shelf.
- **"All stores":** new stores have their own ramp-up story. Their FnV has already recovered to ~97% by week 8.

---

## Phase 9: Evaluate the +20% plan

**Goal:** show what the plan would actually do.

Baseline: the latest week (week 8), Coimbatore, open days. Units only (the data has no prices).

- **Extra needed (unmet demand):** sales rate per in-stock hour × out-of-stock hours. Milk ≈ **7.2k units a week** (old stores 5.6k, new stores 1.5k). FnV ≈ 1.5k a week.
- **Cross-check:** old-store milk sales fell from 250 to 197 per store-day; × 15 stores × 7 days ≈ 5.6k a week, the same as the unmet-demand estimate.
- **FnV +20%:** adds ≈ **16.7k units a week**, but only ≈ 1.5k would sell, so ≈ **15.1k (about 91% of the extra) would be wasted**, on top of the ~11–12% FnV wastage there already is.
- **Milk +20%:** V03 cuts every order by the same %, so +20% ordered → +20% received ≈ **5.3k units a week. All of it would sell** (milk wastage is now ~0.5%), but ≈ **1.9k a week would still be unmet**. Closing the full gap needs ≈ +27% more milk received.
- **Risk on milk:** the uplift only works while V03 keeps short-shipping. If V03 recovers to ~97%, a standing +20% on 2-day-shelf-life milk turns straight into waste. It also hides the vendor problem.
- **Verdict:** the plan is pure waste for FnV. For milk it helps as a **temporary stopgap**, but it must be tied to V03's fill rate and reviewed daily, while the vendor issue is fixed.

---

## Phase 10: Rule out red herrings

| Item | Why it doesn't change the answer |
|---|---|
| Salem FnV dumping spike on 20 Aug | One day, in the other city |
| V11 fill-rate dip in week 6 | Cancelled POs on closed days |
| Week 6 is the worst week | Closures and the V03 break overlap |
| Shelf life vs wastage | No pattern in this data, so don't claim one |
| Baseline weekly cancellations | Unchanged across the period |

---

## Phase 11: Build the recommendation

**Decision:** **Modified plan.**

**Three-line summary:**

1. The real drop is about 6 points, entirely in milk, from 10 Aug. The rest is closures and new stores.
2. The cause is vendor V03 delivering ~71% of milk orders (down from ~97%) at every store and SKU.
3. +20% on FnV would waste ~15k units a week. For milk, a temporary uplift tied to V03's fill rate recovers most lost sales while the vendor is fixed.

**Actions:**

| # | Action | Owner | By when |
|---|---|---|---|
| 1 | Cancel the +20% FnV uplift | Supply planning | Before Monday's POs |
| 2 | Escalate the V03 shortfall with the vendor and get a recovery date | Category / vendor management | Monday |
| 3 | Set up a backup milk supply for Coimbatore (e.g. V04) | Category / sourcing | This week |
| 4 | Temporary milk-only uplift (~+20–27%) while V03 short-ships; review daily and remove as soon as V03's fill rate recovers | Supply planning | From Monday, interim |
| 5 | Report new stores and closures separately in availability reporting | Analytics | Ongoing |

**Monitor next week:** V03 daily fill rate, old-store open-day milk availability, FnV wastage.

---

## Phase 12: Package the submission

1. **Recommendation tab:** decision, 3-line summary, at most 5 key numbers, actions with owner and deadline.
2. **Analysis tabs:** one per finding, each with a one-line purpose in cell B2:
   - `A_headline_vs_clean`: raw vs old stores on open days weekly availability
   - `B_category_split`: Milk vs FnV weekly
   - `C_vendor_fill_rate`: weekly fill rate by vendor plus the daily break on 10 Aug
   - `D_funnel`: ordered → received → sold → dumped, before vs after
   - `E_plan_cost`: lost sales vs the extra units from +20%
   - `F_data_quality`: issues found and how they were handled
3. **Code:** the cleaning script first, then each analysis query in order, each labelled with the number it produces.
4. **AI note:** what AI was used for, plus one place it was corrected. For example:
   - The expected shelf-life → wastage pattern didn't hold in the data.
   - A per-store-day calculation had to be fixed to divide by actual open days rather than stores × 7.

---

## Flow in one line

Understand → Define → **Clean (closures, duplicates, new stores)** → Reproduce → Remove distortion → Locate → Root cause → Test claims → Cost the plan → Rule out noise → Recommend → Package.
