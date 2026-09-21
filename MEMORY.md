# AuctionatorPlus — Development Memory

The single persistent note for this addon. Read it before touching the code instead of re-deriving anything. Created 2026-09-19 from the code, the git history and `README.md` (kept, it is the user-facing doc). **This addon has never been audited for WoW Forever 1.60.x** — unlike its five siblings in this AddOns folder, no compatibility pass has been run on it at all. Section 6 is the work that has not happened.

**Verified against:** `forever` @ `70ef1b2` (1.60.1.69913), 2026-09-21.

**Shared 1.60 client facts are not in this file.** They live in one place: `Cortex/WoW/Forever Client Facts.md` in the Obsidian vault (`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/`). Read that first — this note records only what is specific to this addon, and never restates a fact about the client. Companions there: `Two-Version Addon Architecture.md` (layout), `UI Compatibility Analysis.md` (templates and widgets). Run `../check-client-facts.sh` to see whether any of it has gone stale.

---

## 1. Status on 2026-09-19

| Item | State |
|---|---|
| Version | 2.0.0, **committed and clean**. HEAD `dcae4c9` "Show full scan progress in the button label instead of a tooltip" |
| Repo | `github.com/miyanko-dev/AuctionatorPlus`, branch `main`. No `.pkgmeta`, no CI, no tags |
| Working tree | Only `?? MEMORY.md`. Unlike every sibling addon here, this one has nothing uncommitted |
| Target | Classic Era / Anniversary 1.15.x only, `## Interface: 11509`. **No 16001**, no 1.60 support |
| Hard dependency | `## Dependencies: Auctionator` — the addon does not load without it |
| Soft dependency | TradeSkillMaster_AppHelper plus the TSM desktop app, for the TSM data rows |
| Saved variable | `AuctionatorPlusDB`, account-wide |
| Installed clients | Forever beta only (`_classic_beta_`), never launched. `_classic_era_` is **gone** from this Mac, so the addon cannot run here at all today |
| Offline checks | None run. No harness, no test suite, no `luac -p` pass recorded |
| In-game checks | Last worked on 1.15.x before `_classic_era_` was removed. Nothing verified since |

**The one thing to know:** this is the only miyanko-authored addon in this folder still on a single-client toc, and the only one never checked against `forever`. Everything in section 6 is open.

---

## 2. How to resume

1. `git status` — expect a clean tree plus this file.
2. `luac -p Modules/*.lua` (never recorded as run).
3. To actually run it you need `_classic_era_` reinstalled **and** Auctionator installed there. Neither exists on this Mac.
4. Before any 1.60 work, read section 6 and the shared client facts in `../ChatScan/MEMORY.md` section 8. The blocking question is not this addon's code, it is whether Auctionator itself has a Forever build.

---

## 3. What it is

A companion add-on for [Auctionator](https://www.curseforge.com/wow/addons/auctionator) that adds price-history and gear-pricing tools to the Auction House. It does not replace any Auctionator screen; it hooks into them and adds rows, columns, buttons and one settings page.

Feature summary (the README carries the full user-facing wording):

- **Price-history tooltips** — item tooltips list the Average Price from Auctionator (14 days of minimum buyouts from your own scans) and from TSM, each tagged with its data age, then the Relative Value of the last known price against each, coloured for the active AH view, and the TSM Sale Rate.
- **Show Similar Items / Show Similar Bags** — a checkbox in the Selling tab, visible only while equipment (or a container) sits in the sale slot. Runs a background AH search for the same slot plus armor or weapon type within the level range, narrowed to items carrying every stat of the sale item within the stat value and stat count ranges; weapons must also land within the DPS range. Bags match on slot count regardless of bag type. Results merge into the Selling tab's current-prices panel.
- **Price from comparables** — hover a listed result to preview it, click a similar item's row to take over its exact unit price. Clicking a row of the item itself keeps Auctionator's usual undercut behaviour.
- **Relative Value columns** — a *Relative* column in the shopping results and current-prices listings, against the Auctionator 14-day average or the mean of Auctionator and TSM when both exist.
- **Filter by Stat** — a *Filter* button in the shopping tab opening a stat dialog with match-all or match-any. Persists account-wide, applies until *Reset Filter*, and **only constrains equipment** so a consumable search never comes back empty from a leftover gear filter.
- **Green bag glow** — in the Selling tab's bag panel, items whose last known price beats their Average Price by the sell threshold get the game's own `bags-glow-green` atlas faded over the icon.
- **Full Scan buttons** in the shopping tab and the Selling tab's bottom row, with a progress readout in the button label.
- **Sale Scan** — a button right of the Selling tab money display that runs a live exact-name price search for every distinct bag item, sequentially and throttle-aware, first page only.
- **TSM data rows and Sale Rate** — captured from the TSM desktop app on login.
- **Settings panel and Guide.**

---

## 4. Architecture

Flat `Modules/` folder, 16 files, 2,508 lines, loaded in dependency order by the toc. There is **no `Core/` + `UI/` split** and no version seam — it predates the convention the sibling addons adopted on 2026-09-19.

Toc load order:

```
Modules\Init.lua          Modules\Bridge.lua        Modules\Panel.lua
Modules\StatScan.lua      Modules\PriceHistory.lua  Modules\TrendColumn.lua
Modules\BagGlow.lua       Modules\SaleScan.lua      Modules\SellingWatch.lua
Modules\ShoppingFilter.lua Modules\FullScanButton.lua Modules\TSMFeed.lua
Modules\Guide.lua         Modules\Settings.lua      Modules\Bootstrap.lua
```

| File | Lines | Holds |
|---|---|---|
| `Init.lua` | 22 | `AP.Defaults`, `AP.DB()` (account store, lazily created) |
| `Bridge.lua` | 49 | **The only file that talks to Auctionator internals.** Wraps them, `pcall`s where Auctionator can raise on bad input. The de facto seam |
| `Panel.lua` | 111 | Shared dialog look: AceGUI-style backdrop, three-piece header banner from `UI-DialogBox-Header`, corner close, gold section headings, full-width buttons, height fit |
| `StatScan.lua` | 252 | Reads item stats off a hidden scan tooltip named `AuctionatorPlusScanTooltip`, lowercased, because **`C_TooltipInfo` does not exist on era**. Handles "+N Stat", "Stat increased by N", "+N to all attributes", school damage and resistance lines, and keeps creature-specific and form-only bonuses apart from plain ones |
| `PriceHistory.lua` | 176 | 14-day interquartile mean of daily minimum buyouts. `HISTORY_WINDOW_DAYS = 14` to match TSM's market value; `MIN_TRIM_SAMPLES = 8` below which the median is used instead. Matches Auctionator's own day index (days since `SCAN_DAY_0`) via each entry's `rawDay` |
| `TrendColumn.lua` | 136 | Appends *Relative* and *Sale Rate* columns to Auctionator's listings, each storing a display string plus a numeric sort key on every result entry. Funds the columns from the flexible name column in the wide shopping listing; the narrow buy listing drops Auctionator's "You?" column instead |
| `BagGlow.lua` | 59 | Post-hooks the bag-button mixin before any buttons exist, so recycled buttons drop the glow on their own when an item stops being favorable |
| `SaleScan.lua` | 241 | Sequential exact-name search per distinct bag item. `RETRY_SECONDS = 0.5`, `MAX_RETRIES = 6` because the bag view fills asynchronously after the tab opens |
| `SellingWatch.lua` | 587 | The largest file. Similar-item matching: `NON_GEAR_SLOTS` rejection, slot grouping (robes share the chest slot, main/off-hand-only weapons share the generic one-hand slot), `REDROP_DEBOUNCE = 1.0` to absorb the burst of `StartFakeBuyLoading` repeats one placement fires, a token that bumps per placement and supersedes in-flight work, and `saleKind` (`"gear"` / `"bag"` / nil) driving the checkbox label |
| `ShoppingFilter.lua` | 281 | The stat filter dialog, two columns, `FILTER_ORDER` matching `AP.StatScan.FullStatSet` |
| `FullScanButton.lua` | 183 | Both full-scan buttons, progress in the label, `FINAL_HOLD_SECONDS = 2`, `FADE_DURATION = 0.3` |
| `TSMFeed.lua` | 229 | Wraps the global `TSM_APPHELPER_LOAD_DATA` that `AppData.lua` calls **while addons load**, forwarding to TSM untouched, and decodes `AUCTIONDB_NON_COMMODITY_DATA`, `AUCTIONDB_NON_COMMODITY_SCAN_STAT` and `AUCTIONDB_REGION_SALE` for this realm and region. Matches keys the way AppHelper does: case-insensitive, curly apostrophes squashed |
| `Guide.lua` | 40 | Once-per-character login guide, `WIDTH = 440` |
| `Settings.lua` | 88 | Options page under Options > AddOns via `Settings.RegisterVerticalLayoutCategory`, plus the button next to Auctionator's own "Open Addon Options" |
| `Bootstrap.lua` | 54 | `PLAYER_LOGIN` registers settings and shows the guide; `AUCTION_HOUSE_SHOW` runs `ensureButtons` |

### The bootstrap retry loop

Auctionator creates its host frames on or shortly after the first AH open, so every UI piece is created by an `Ensure` function that returns true once its frame exists. `ensureButtons` retries all of them every 0.5 s for up to 20 attempts. `ENSURES` order matters where one button anchors to another:

```
AP.FullScanButton.Ensure → hookBuyFrame → AP.SellingWatch.Ensure →
AP.SaleScan.Ensure → AP.ShoppingFilter.Ensure → AP.SettingsPanel.EnsureButton
```

`hookBuyFrame` hides the shopping full-scan button while `AuctionatorBuyFrame` covers the results inset.

### Auctionator surface consumed (all through `Bridge.lua` except where noted)

`Auctionator.API.v*`, `Auctionator.EventBus` (8 call sites), `Auctionator.AH.Events`, `Auctionator.Selling.Events`, `Auctionator.Buying.Events`, `Auctionator.FullScan.Events`, `Auctionator.AH.QueryAuctionItems`, `Auctionator.AH.AbortQuery`, `Auctionator.AH.IsNotThrottled`, `Auctionator.Database`, `Auctionator.Database.GetPriceHistory`, `Auctionator.Database.GetPriceAge`, `Auctionator.Search.GetCleanItemLink`, `Auctionator.Search.GroupResultsForDB`, `Auctionator.Utilities.DBKeyFromLink`, `Auctionator.Utilities.BasicDBKeyFromLink`, `Auctionator.Utilities.IsEquipment`, `Auctionator.Utilities.CreatePaddedMoneyString`, `Auctionator.Constants.SORT`, `Auctionator.Constants.SCAN`, `Auctionator.Locales.Apply`, `Auctionator.State.FullScanFrameRef`, `Auctionator.Shopping.Tab`.

Global frames hooked directly: `AuctionatorBuyFrame`, `AuctionatorShoppingFrame`.

**This is the real risk surface.** These are Auctionator internals, not a published API, and they move between Auctionator releases.

### Saved variables — `AuctionatorPlusDB`

Account-wide, created lazily by `AP.DB()`. Holds the settings keys below (the settings panel uses the same keys as its variable keys), the shopping stat filter, and per-character guide flags.

| Key | Default | Range / meaning |
|---|---|---|
| `sellThresholdPct` | 15 | 5–100, step 1. Bag items glow green once a Relative Value reaches this |
| `glowRequireBoth` | true | Checkbox. Both Auctionator and TSM Relative Values must reach the threshold where TSM has data; unchecked, one is enough |
| `minSaleRate` | 0 | 0–100, step 5. Items under this TSM sale rate never glow. 0 = off |
| `levelTolerance` | 2 | 0–10, step 1. Comparable gear's required level band |
| `dpsTolerancePct` | 20 | 0–50, step 5. Comparable weapon DPS band |
| `statValueTolerance` | 30 | 0–100, step 5. Per-stat value band |
| `statCountTolerance` | 0 | 0–5, step 1. Allowed difference in total stat count |
| `guideAtLogin` | true | Show the guide once per character at login |

One migration exists, in `AP.SettingsPanel.Register`: the login toggle used to be `db.tsmHint`, carried over to `db.guideAtLogin` and the old key cleared. Every slider and checkbox change calls `AP.BagGlow.Repaint`, because painted glows depend on the threshold and the both-values rule.

---

## 5. Known behaviour worth not re-deriving

- **`C_TooltipInfo` does not exist on Classic Era**, which is why `StatScan.lua` scrapes a hidden named scan tooltip instead. On 1.60 `C_TooltipInfo.GetItem` would exist and would be the better path — but only once the rest of section 6 is settled.
- **Price history uses an interquartile mean, not an average.** Dropping the cheapest and priciest quarter removes dump days and thin-supply days by construction, with no tuning constants to misjudge a market. Below `MIN_TRIM_SAMPLES = 8` a quartile trim is too thin to stop same-side freak days, so the median is used.
- **The similar-items search runs in the background on the Selling tab**, with no tab switching, and merges into the current-prices listing alongside Auctionator's own name-based results.
- **Sale Scan reads only the first page per item**, because results arrive cheapest-first and only the lowest price matters. It steps aside as soon as the player places an item for sale or runs their own search.
- **TSM data is captured by wrapping a global the TSM app helper calls during addon load.** TSM itself receives the payload unchanged. Without the desktop app running, the TSM rows stay hidden rather than showing zeros.
- **The stat filter constrains equipment only.** Consumables, trade goods and other non-equipment results always pass through.
- **Bag glow uses `bags-glow-green`**, a premade atlas chosen because it is bright under ADD blending and stays visible next to green-quality item borders.

---

## 6. Open: nothing about 1.60 has been checked

This is the entire outstanding work. Ordered by what blocks what.

1. **Does Auctionator have a WoW Forever build at all?** This addon has `## Dependencies: Auctionator` and consumes two dozen Auctionator internals. If Auctionator does not ship a Camelot toc, AuctionatorPlus cannot run on 1.60 no matter what its own code does. **Settle this first; everything below is moot until it is answered.**
2. **Does the 1.60 auction house resemble the Classic one at all?** Forever runs the Mainline engine (see `../ChatScan/MEMORY.md` and `../TargetFinder/MEMORY.md` section 3), which means the **retail auction house**, not the Classic one. Auctionator's Classic and Retail code paths are substantially different addons internally. Every frame name this addon hooks (`AuctionatorBuyFrame`, `AuctionatorShoppingFrame`, the Selling tab bag panel, the current-prices listing) is a Classic-side name. Expect most of the UI integration to need rewriting rather than porting.
3. **`## Interface: 11509` only.** No 16001. Adding it is one line but pointless before 1 and 2.
4. **`C_TooltipInfo` on 1.60** would replace the hidden scan tooltip in `StatScan.lua`, and is confirmed present on `forever` (`../TargetFinder/MEMORY.md` section 12). Note the caveat there: `C_TooltipInfo.GetUnit` is `SecretArguments = AllowedWhenUntainted`; the item variants were not separately checked.
5. **`Settings.RegisterVerticalLayoutCategory`, `Settings.RegisterAddOnSetting`, `CreateSettingsListSectionHeaderInitializer`, `CreateSettingsButtonInitializer`, `MinimalSliderWithSteppersMixin.Label.Right`.** The `Settings` API is confirmed as 62 functions identical on both clients (`../ChatScan/MEMORY.md` sources), so the settings page itself is the least of the problems.
6. **`UI-DialogBox-Header` and the AceGUI-style backdrop in `Panel.lua`.** Same unverified-texture risk PlayerArmoryLink carries: on the `forever` tree that texture is referenced only from Classic-gated files. See `../PlayerArmoryLink/MEMORY.md` assumption 4. A missing texture renders as a green or black block, a visual check not a crash.
7. **No structural audit has been done.** No `luac -p` run recorded, no toc-resolution check, no globals extraction, none of the things the sibling addons had done to them on 2026-09-18/19.

---

## 7. Next development steps

Nothing here needs beta access except step 4.

1. **Run the basic offline checks that every sibling addon has had and this one has not:** `luac -p Modules/*.lua`, confirm all 16 toc entries resolve case-sensitively, confirm nothing on disk is unlisted, extract global writes and check they are `AuctionatorPlusDB` only.
2. **Decide whether 1.60 is even a goal.** Answer open question 1. If Auctionator has no Forever build, write that down here and stop; this addon stays a 1.15.x tool.
3. **If 1.60 is a goal**, do not add `16001` to the toc as a first step. Audit against `Gethe/wow-ui-source@forever` the way the siblings were audited, and expect the answer to be "this is a rewrite of the integration layer, not a port".
4. **Reinstall `_classic_era_` plus Auctionator** if the addon is to be exercised at all. It currently cannot run on this machine.
5. **Optional, independent of all the above:** restructure `Modules/` into the `Core/` + `UI/` shape the siblings use, with `Bridge.lua` becoming the explicit seam it already is in practice. Only worth doing if step 2 says 1.60 is a goal.
6. **Consider pinning the Auctionator version** the addon is known to work against, in the README or the toc notes. Two dozen internals is a large unversioned surface.

---

## 8. Test results

Empty. The addon worked on 1.15.x before `_classic_era_` was removed from this Mac; nothing is recorded per-feature.
