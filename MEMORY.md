# AuctionatorPlus — Memory

Updated 2026-09-30 after the Forever-only rework (4.0.0). The owner's decision: WoW Forever 1.60.x only. `main` holds only the Forever version, and `1.15.x-backup` keeps the dual-client 3.0.0 with all Classic code.

Verified against:

- Gethe `forever` @ `966519cf` (1.60.1.70124), only files the Forever client loads
- Ketho `forever` @ `4149af64` (1.60.1.70009)
- the installed Auctionator 339 (its mainline/camelot load set: `Source/`, `Source_Mainline/`, `Source_ModernAH/`, `Source_Forever/`) and TradeSkillMaster v4.14.77
- the installed client 1.60.1.70009

Nothing has run in a client. `luac -p` passes on all 15 Lua files. A stubbed load test (session scratchpad, not kept in the repo) loaded the toc in order against mocks and the real enUS strings and passed 50/50: load, login and AH-open bootstrap, default seeding, the stat parser, the AP-1 gating/yield/timeout paths and the AP-12 Sale Scan paths.

## Current state

A companion for Auctionator that adds:

- Price-history and Relative Value tooltip rows.
- *Relative* and *Sale Rate* columns.
- A Shopping stat filter.
- Show Similar Items and Show Similar Bags in the Selling tab.
- Bag glow, Sale Scan and Full Scan buttons.
- A settings page and a one-time Guide.

| Item | State |
|---|---|
| Version | 4.0.0. `## Interface: 16001`, `## Category: Auctions`, `## IconTexture: 133784`, `## Dependencies: Auctionator`, `## OptionalDeps: TradeSkillMaster`, `## SavedVariables: AuctionatorPlusDB`. No compartment entry, no slash command |
| Git | `1.15.x-backup` = `origin/1.15.x-backup` = `a4e59d8` (3.0.0, dual-client, last commit with Classic code). `main` has two local commits on top of `a4e59d8`, not pushed: the split/UI commit `c3186b4` and the fixes commit. History is linear. No tags |
| Lua | 3,105 lines in 28 files before, 2,184 lines in 15 files after |

Layout:

- `Modules/` is the logic folder, one file per feature. A feature module owns both its Auctionator hooks and the widgets it places inside Auctionator's AH frames (Full Scan, Sale Scan, Filter/Reset, the Show Similar checkbox), so those stay with their feature.
- `UI/` holds the UI-only files: `Panel.lua` (dialog builder and the shared tab button), `Guide.lua`, `Settings.lua`.
- Load order: `Init, Bridge, ItemStats, TSM, PriceHistory, TrendColumn, BagGlow, UI/Panel, SimilarItems, ShoppingFilter, FullScanButton, SaleScan, UI/Guide, UI/Settings, Bootstrap`. `ShoppingFilter` reads `AP.Panel.INSET` at load, and `Bootstrap` builds its list from every module at load, so it stays last.

Auctionator internals in use, all verified 2026-09-30 in Auctionator 339's mainline/camelot load set:

- Mixins:
  - ShoppingTab, Search and BuyItem data providers (`GetTableLayout`, `Sort`, `PrettifyData`, `AppendEntries`)
  - `AuctionatorSellSearchRowMixin.OnClick`
  - `AuctionatorGroupsViewItemMixin.SetItemInfo`
- Frames:
  - `AuctionatorShoppingFrame` (`.DataProvider`, `.ShoppingResultsInset`, `.ExportCSV`, `.searchRunning`)
  - `AuctionatorSellingFrame` (`.BagListing.View.itemMap`, `.BagInset`, `.HistoricalPriceInset`, `.CurrentPricesProvider`, `.SaleItemFrame.itemInfo`)
  - `AuctionatorConfigFrame.OptionsButton`
  - `Auctionator.State.FullScanFrameRef`, and `Auctionator.State.IncrementalScanFrameRef.doingFullScan`
- Utilities: `IsEquipment`, `CreatePaddedMoneyString`, `DBKeyFromLink`, `ItemKeyString`, `DBKeyFromBrowseResult`.
- Database: `GetFirstPrice`, `GetPriceAge`, `GetPriceHistory`, `SetPrice`. Plus the EventBus.
- AH wrappers: `SendBrowseQuery`, `HasFullBrowseResults` (false until the queued browse was actually sent), `RequestMoreBrowseResults`, `SendSellSearchQueryByItemKey`, `SendSearchQueryByItemKey`.
- Constants: `SCAN_DAY_0`, `SORT`, `ItemResultsSorts`, `CommodityResultsSorts`, `ITEM_TYPES`.
- Events: `SellSearchStart(itemKey, link, originalKey)`, `ClearBagItem`, `PriceSelected`, `RefreshSearch`, `ItemSearchResultsReady`/`CommoditySearchResultsReady`, `FullScan.Events`, `Shopping.Tab.Events.SearchStart` (`"shopping tab search start"`), `IncrementalScan.Events.ScanStart` (`"full_incremental_scan_start"`, `Source_ModernAH/IncrementalScan/Events.lua`).
- Field reads are internals, not API: `searchRunning` is set in `DoSearch` and cleared by `StopSearch` and the end callback (`Source/Tabs/Shopping/Mixins/Main.lua:22,29,112`); `doingFullScan` by `InitiateScan`/`NextStep`/AH close (`Source_ModernAH/IncrementalScan/Mixins/Frame.lua`); `itemInfo` by the sale item's click and reset (`SaleItem.lua:138,157,210`). A rename reads as nil, which only disables the guard.

Other facts:

- Stat parser: matches the client's own `ITEM_MOD_*` / `_SHORT` strings in long and short form. It parses `%d` and skips inactive `(2) Set:` lines. All 83 stat string names and all 25 filter stats exist on Forever. The Stat Filter always lists all 25; saved keys it doesn't list are dropped.
- Auctionator on Forever:
  - Its Full Scan defaults to the incremental browse scan (`REPLICATE_SCAN` = false, `Source/Config/Main.lua:89`). Its incremental scan frame listens to every browse event, even when it is not scanning.
  - Price keys for gear below item level 168 are the bare item ID (`DBKeyFromBrowseResult.lua:9`, `Constants/Main.lua:39`), so suffix variants share one history.
  - Exact-copper pricing is decided by `Constants.IsForever` (`SaleItem.lua:8-12`), not `SupportsCopperValues`.
  - Its own sell search records `buyoutAmount or bidAmount` of the first result (`SaleItem.lua:562`); the Plus Sale Scan records the cheapest buyout instead.
  - Missing-term shopping placeholders carry item key 1217, "Unknown Reward" (`Source_ModernAH/Search/EmptyResult.lua:4-9`). It isn't equipment, so the Stat Filter keeps them.
- TSM via `TSM_API` only.
  - v4.14.77's toc is `120100, 50504, 20506, 11509`, with no 16001, so it's absent on Forever.
  - If forced to load, LibTSMCore asserts a known `WOW_PROJECT_ID` (`Core.lua:23-33`), and its Classic AH code needs `QueryAuctionItems`, which Forever lacks.
  - `GetCustomPriceValue` rounds to a whole number and turns 0 into nil (`Object.lua:183`, `CustomString.lua:247`).
- Native UI:
  - The Guide and the Stat Filter are `UI/Panel.lua` dialogs: `DialogBorderTemplate` as `.Border`, `DialogHeaderTemplate` as `.Header` with `Header:Setup(title)` (the template anchors itself TOP +11), `UIPanelCloseButton` at TOPRIGHT -2/-2, DIALOG strata, toplevel, clamped, drag-movable, Escape via `UISpecialFrames`, content 40 px below the top with 20 px side and bottom padding (`Blizzard_SharedXML/Shared/Dialog/DialogTemplates.xml`, as in `MainMenuFrameTemplates.xml`).
  - Settings use `Settings.RegisterVerticalLayoutCategory` with `RegisterAddOnSetting`, `CreateCheckbox`, `CreateSlider` and a button initializer, opened with `Settings.OpenToCategory(category:GetID())` from the Auctionator tab button and the Guide.
  - Buttons inside Auctionator's frames match their neighbours: Full Scan and Sale Scan are fixed 110x22 `UIPanelButtonTemplate` (their labels change during a scan), Filter, Reset and the options button are `UIPanelDynamicResizeButtonTemplate` like Auctionator's Export Results and Open Addon Options.
  - Text uses Blizzard font objects only. Tooltip rows use `GameTooltip_AddColoredDoubleLine` with `HIGHLIGHT_FONT_COLOR` and `GameTooltip_AddBlankLineToTooltip`. The bag glow is Blizzard's own `bags-glow-green` atlas (`Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml:121`).
  - No tool window, scroll frame or minimap button exists, so spec items 1, 2 and 8 don't apply.
- The Addon Compartment is available on Forever. There is no entry (AP-15, blocked).

## Audit 2026-09-30: status after 4.0.0

Done in 4.0.0:

| ID | What was done |
|---|---|
| AP-1 | Similar Items: the browse yields on `Shopping.Tab.Events.SearchStart`, `IncrementalScan.Events.ScanStart` and `AuctionatorSellingFrame` OnHide. It doesn't start while `AuctionatorShoppingFrame.searchRunning` or `IncrementalScanFrameRef.doingFullScan` is true. The item-load fan-out evaluates once, at the last load or after 5 s, whichever is first; uncached candidates don't match. A browse that already finished isn't cancelled by a new search or scan, since its rows no longer need the result set |
| AP-5 | toc per the shared standard, 4.0.0, no per-line tags |
| AP-6 | `Modules/Era/` deleted (891 lines) |
| AP-7 | `Modules/Forever/*` merged into the shared modules, `SaleScan.lua` moved to `Modules/`, single-use exports made local (`AP.Tooltip`, `AP.TrendColumn`, the `AP.SimilarItems` helpers, `FullScanButton.Create`, `Bridge.KeysForLink`, `Bridge.Fire`) |
| AP-8 | Only the DiamondMetal dialog stays, per spec item 6 |
| AP-9 | `RATED_GEAR`/`RATED_STATS` gone. The filter uses the full list and drops unknown saved keys |
| AP-10 | `tsmHint` migration deleted |
| AP-11 | `drop`/`flex`/`flexCopy`, `Bridge.Register`/`Unregister` removed. `Register` is inlined into `Listen` |
| AP-12 | Sale Scan refuses while an item is slotted (tooltip shows an error line), passes `true` to split owned auctions, and records the cheapest result with a buyout |
| AP-13 | `AP.DB()` seeds missing defaults itself, once per saved table |
| AP-14 | Shared `AP.BagGlow.EachButton`, `AP.Panel.CreateTabButton`, ItemStats `itemOf` and `escapePattern`. The placeholder comment is fixed, and `Bridge.ShoppingItemRef` is inlined |
| AP-16 | All files 100644 |
| AP-17 | README, Guide, TSM, Bridge and ItemStats text for Forever only |

Still open, blocked on the owner (behaviour unchanged in 4.0.0):

| ID | Severity | Finding | Options |
|---|---|---|---|
| AP-2 | Medium | The Plus Full Scan always starts the replicate scan (`Bridge.StartFullScan` → `FullScanFrameRef`) and listens only to `FullScan.Events`. Auctionator's own button follows `REPLICATE_SCAN` (default incremental). UNVERIFIED that `ReplicateItems` completes on Forever servers | Follow Auctionator's mode like `ScanButton.lua:3-8` and listen to both event sets (about +10 lines), or keep forcing replicate |
| AP-3 | Medium | `GetCustomPriceValue("DBRegionSaleRate")` returns nil or 1 (shown as 100%), because TSM rounds a 0–1 fraction. The Sale Rate column, the tooltip row and the minimum-sale-rate gate are wrong wherever TSM runs. Dormant on Forever | Ask for a scaled value (e.g. `"DBRegionSaleRate * 1000"`, syntax UNVERIFIED), or drop sale rate |
| AP-4 | Medium | TSM-only parts never work on Forever today: the Sale Rate column (always blank), "Require both values", "Minimum sale rate", the TSM tooltip rows and the Guide TSM section | Build the TSM UI only when `TSM_API` exists at load, or remove TSM until it ships 16001 (about −90 lines) |
| AP-15 | Low | No `## AddonCompartmentFunc` | Add one that opens settings |
| AP-18 | Low | The glow hook also paints the Selling tab's sale-slot icon (`BagItemSelected.lua:3-4`) | Keep, or skip the sale-slot icon |

New questions from the rework:

- No slash command exists. Settings open only from the Auctionator tab button and the Guide. Adding `/ap` means one `SlashCmdList` entry in `UI/Settings.lua` calling `AP.SettingsPanel.Open`.
- A Similar browse skipped because a shopping search or incremental scan was running doesn't retry. The player has to press Refresh or re-slot the item. Options: keep that; retry on `IncrementalScan.Events.ScanComplete`/`ScanFailed` while the item is still slotted (about +10 lines); or show a line in the checkbox tooltip.

## Blockers, issues, challenges

1. The addon depends on about 20 unguarded Auctionator 339 internals (listed above). A renamed function or mixin in Auctionator aborts a whole file.
2. The TSM features stay off on Forever until TSM ships a 16001 build. Where TSM runs, sale rate is broken (AP-3).
3. Forever item stat wording can't be verified offline. Whether Forever browse item keys carry the random-suffix id is unknown.
4. The Similar browse still reacts to other addons' or Blizzard's own browse queries, which Auctionator doesn't announce.

## Next steps

1. Owner decisions: AP-2, AP-3/AP-4 (TSM), AP-15, AP-18, the slash command and the Similar retry.
2. Push `main` once the in-game checks below pass.
3. Enable only Auctionator and AuctionatorPlus, then run `/console scriptErrors 1` and `/reload`.

Forever checks:

- [ ] The AddOns list shows Auctionator Plus 4.0.0 under Auctions, not out of date.
- [ ] No errors at login or on the first AH open.
- [ ] A bag item and a chat link show the Auctionator average and Relative Value, in white rows after a blank line.
- [ ] Shopping: *Relative* and *Sale Rate* sort with blanks last. Full Scan, Filter and Reset sit on the Export row.
- [ ] Selling, Show Similar Items: left-click takes the exact price, right-click does nothing, shift links, ctrl previews. Show Similar Bags matches slot count.
- [ ] Sale Scan counts, cancels and stops on item select. With an item slotted, a click does nothing and the tooltip shows the red line. Full Scan goes green, and a second click gives Auctionator's cooldown message.
- [ ] Settings persist across `/reload`. A fresh WTF shows the defaults before the settings panel is opened.
- [ ] The Guide and the Stat Filter show the DiamondMetal border and header, with the close button in the corner and text 20 px from the edges. Escape closes both.
- [ ] `/dump TSM_API` prints nil, and no TSM rows show.
- [ ] Stat Filter shows 25 stats, none clipped.
- [ ] AP-1: start Auctionator's incremental Full Scan, then slot gear with Show Similar Items on. No comparables appear, and the scan finishes normally. Slot gear, then switch to Shopping and search at once: shopping results are complete.
- [ ] `/dump C_AuctionHouse.GetBrowseResults()[1].itemKey` on an "of the X" item: is the suffix id present?
- [ ] `/dump WOW_PROJECT_ID`.
- [ ] Record the stat wording: `/run local t=C_TooltipInfo.GetHyperlink(select(2,C_Item.GetItemInfo(<id>))) for _,l in ipairs(t.lines) do print(l.leftText) end`.
