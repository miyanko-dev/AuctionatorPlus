# AuctionatorPlus — Memory

Updated 2026-09-30 after the Forever-only rework (4.0.0) and the owner decisions of round 2 (still 4.0.0, not shipped). The owner's decision: WoW Forever 1.60.x only. `main` holds only the Forever version, and `1.15.x-backup` keeps the dual-client 3.0.0 with all Classic code.

Verified against:

- Gethe `forever` @ `966519cf` (1.60.1.70124), only files the Forever client loads
- Ketho `forever` @ `4149af64` (1.60.1.70009)
- the installed Auctionator 339 (its mainline/camelot load set: `Source/`, `Source_Mainline/`, `Source_ModernAH/`, `Source_Forever/`) and TradeSkillMaster v4.14.77
- the installed client 1.60.1.70009

Nothing has run in a client. `luac -p` passes on all 15 Lua files. A stubbed load test (session scratchpad, not kept in the repo) loads the toc in order against mocks and the real enUS strings and passes 87/87: load, login and AH-open bootstrap, default seeding, the stat parser, the AP-1 gating/yield/timeout paths, the AP-12 Sale Scan paths, the sale-rate removal, the AP-2 scan-mode routing, labels and shopping-search refusal (incremental mode only), and the Similar retry paths. Mutations of the new code (no resume, no visibility check, no frame delay, always replicate, replicate events only, no refusal, no red line, refusal in both modes) each fail it.

## Current state

A companion for Auctionator that adds:

- Price-history and Relative Value tooltip rows.
- A *Relative* column.
- A Shopping stat filter.
- Show Similar Items and Show Similar Bags in the Selling tab.
- Bag glow, Sale Scan and Full Scan buttons.
- A settings page and a one-time Guide.

| Item | State |
|---|---|
| Version | 4.0.0. `## Interface: 16001`, `## Category: Auctions`, `## IconTexture: 133784`, `## Dependencies: Auctionator`, `## OptionalDeps: TradeSkillMaster`, `## SavedVariables: AuctionatorPlusDB`. No compartment entry, no slash command |
| Git | `1.15.x-backup` = `origin/1.15.x-backup` = `a4e59d8` (3.0.0, dual-client, last commit with Classic code). `main` has local commits on top of `a4e59d8`, not pushed (`git log origin/main..main`): the split/UI commit `c3186b4`, the fixes commit `1e3f8d3`, the round-2 decisions commit `58fc9c7`, then the Full Scan refusal (`ad84029`), its limit to incremental mode (`7e32b61`), its tooltip wording (`39f58c2`) and this MEMORY.md fix. History is linear. No tags |
| Lua | 3,105 lines in 28 files before the split, 2,184 in 15 after it, 2,208 in 15 after round 2 |

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
  - `Auctionator.State.FullScanFrameRef` and `Auctionator.State.IncrementalScanFrameRef` (`InitiateScan`, `.doingFullScan`), created on AH show (`Source_ModernAH/Core/Mixin.lua:3-47`)
- Config: `Auctionator.Config.Get(Auctionator.Config.Options.REPLICATE_SCAN)` (`"replicate_scan_3"`, `Source/Config/Main.lua:12,89,219`), read at click time exactly like `Source_ModernAH/Tabs/Auctionator/Mixins/ScanButton.lua:3-8`.
- Utilities: `IsEquipment`, `CreatePaddedMoneyString`, `DBKeyFromLink`, `ItemKeyString`, `DBKeyFromBrowseResult`.
- Database: `GetFirstPrice`, `GetPriceAge`, `GetPriceHistory`, `SetPrice`. Plus the EventBus.
- AH wrappers: `SendBrowseQuery`, `HasFullBrowseResults` (false until the queued browse was actually sent), `RequestMoreBrowseResults`, `SendSellSearchQueryByItemKey`, `SendSearchQueryByItemKey`.
- Constants: `SCAN_DAY_0`, `SORT`, `ItemResultsSorts`, `CommodityResultsSorts`, `ITEM_TYPES`.
- Events: `SellSearchStart(itemKey, link, originalKey)`, `ClearBagItem`, `PriceSelected`, `RefreshSearch`, `ItemSearchResultsReady`/`CommoditySearchResultsReady`, `Shopping.Tab.Events.SearchStart`/`SearchEnd` (`Source/Shopping/Events.lua:13-14`), and all four `ScanStart`/`ScanProgress`/`ScanComplete`/`ScanFailed` of both `FullScan.Events` (`"replicate_scan_*"`) and `IncrementalScan.Events` (`"full_incremental_scan_*"`, `Source_ModernAH/{FullScan,IncrementalScan}/Events.lua`). Auctionator's own scan status listens to the same eight (`Source_ModernAH/Tabs/Auctionator/Mixins/ScanStatus.lua:4-13`).
- `SearchEnd` also fires when a running search is stopped (`AbortSearch` calls the completion callback, `Source/Search/Mixins/MultiSearchMixin.lua:33-40`), including `DoSearch`'s stop right before the next `SearchStart` and the Shopping tab's `OnHide`. `IncrementalScan.Events.ScanFailed` fires only on AH close (`Source_ModernAH/IncrementalScan/Mixins/Frame.lua:48-51`).
- All of the above sit in files of the mainline/camelot load set (`Source/Manifest.xml`, `Source_ModernAH/Manifest.xml` tagged `cata, mists, mainline`); `Source_Forever/Constants.lua` overrides none of them.
- Field reads are internals, not API: `searchRunning` is set in `DoSearch` and cleared by `StopSearch` and the end callback (`Source/Tabs/Shopping/Mixins/Main.lua:22,29,112`); `doingFullScan` by `InitiateScan`/`NextStep`/AH close (`Source_ModernAH/IncrementalScan/Mixins/Frame.lua`); `itemInfo` by the sale item's click and reset (`SaleItem.lua:138,157,210`). A rename reads as nil, which only disables the guard.

Other facts:

- Stat parser: matches the client's own `ITEM_MOD_*` / `_SHORT` strings in long and short form. It parses `%d` and skips inactive `(2) Set:` lines. All 83 stat string names and all 25 filter stats exist on Forever. The Stat Filter always lists all 25; saved keys it doesn't list are dropped.
- Auctionator on Forever:
  - Its Full Scan defaults to the incremental browse scan (`REPLICATE_SCAN` = false, `Source/Config/Main.lua:89`). The Plus Full Scan follows the same setting since round 2 (AP-2). Its incremental scan frame listens to every browse event, even when it is not scanning.
  - Price keys for gear below item level 168 are the bare item ID (`DBKeyFromBrowseResult.lua:9`, `Constants/Main.lua:39`), so suffix variants share one history.
  - Exact-copper pricing is decided by `Constants.IsForever` (`SaleItem.lua:8-12`), not `SupportsCopperValues`.
  - Its own sell search records `buyoutAmount or bidAmount` of the first result (`SaleItem.lua:562`); the Plus Sale Scan records the cheapest buyout instead.
  - Missing-term shopping placeholders carry item key 1217, "Unknown Reward" (`Source_ModernAH/Search/EmptyResult.lua:4-9`). It isn't equipment, so the Stat Filter keeps them.
- TSM via `TSM_API` only, for `DBMarket` alone since round 2.
  - v4.14.77's toc is `120100, 50504, 20506, 11509`, with no 16001, so it's absent on Forever.
  - If forced to load, LibTSMCore asserts a known `WOW_PROJECT_ID` (`Core.lua:23-33`), and its Classic AH code needs `QueryAuctionItems`, which Forever lacks.
  - `GetCustomPriceValue` rounds to a whole number and turns 0 into nil (`Object.lua:183`, `CustomString.lua:247`). That is why a 0–1 source such as `DBRegionSaleRate` came back as nil or 1 (AP-3).
- Native UI:
  - The Guide and the Stat Filter are `UI/Panel.lua` dialogs: `DialogBorderTemplate` as `.Border`, `DialogHeaderTemplate` as `.Header` with `Header:Setup(title)` (the template anchors itself TOP +11), `UIPanelCloseButton` at TOPRIGHT -2/-2, DIALOG strata, toplevel, clamped, drag-movable, Escape via `UISpecialFrames`, content 40 px below the top with 20 px side and bottom padding (`Blizzard_SharedXML/Shared/Dialog/DialogTemplates.xml`, as in `MainMenuFrameTemplates.xml`).
  - Settings use `Settings.RegisterVerticalLayoutCategory` with `RegisterAddOnSetting`, `CreateCheckbox`, `CreateSlider` and a button initializer, opened with `Settings.OpenToCategory(category:GetID())` from the Auctionator tab button and the Guide.
  - Buttons inside Auctionator's frames match their neighbours: Full Scan and Sale Scan are fixed 110x22 `UIPanelButtonTemplate` (their labels change during a scan), Filter, Reset and the options button are `UIPanelDynamicResizeButtonTemplate` like Auctionator's Export Results and Open Addon Options.
  - Text uses Blizzard font objects only. Tooltip rows use `GameTooltip_AddColoredDoubleLine` with `HIGHLIGHT_FONT_COLOR` and `GameTooltip_AddBlankLineToTooltip`. The Full Scan tooltip's replicate-mode line uses `GameTooltip_AddNormalLine` (`Blizzard_SharedXML/SharedTooltipTemplates.lua:142`). The bag glow is Blizzard's own `bags-glow-green` atlas (`Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml:121`).
  - No tool window, scroll frame or minimap button exists, so spec items 1, 2 and 8 don't apply.
- The Addon Compartment is available on Forever. There is no entry (AP-15, blocked).
- Colours and chat (cross-addon rule, round 2): the addon has no literal `|cff` codes. Colours come from `GREEN_FONT_COLOR`, `RED_FONT_COLOR` and `HIGHLIGHT_FONT_COLOR` (`WrapTextInColorCode`, `GameTooltip_AddColoredDoubleLine`). The addon prints no chat lines, so the shared `[Auctionator Plus]:` prefix has no user yet. A future chat line must start with `YELLOW_FONT_COLOR:WrapTextInColorCode("[Auctionator Plus]:") .. " "`. The chat lines a Plus Full Scan triggers ("Starting a full scan ...", cooldown, "Finished processing") are Auctionator's own.

## Sale rate: removed until TSM ships for Forever

The owner removed the sale-rate feature in round 2. It will be re-implemented once TradeSkillMaster ships a full WoW Forever build and it is known whether TSM can provide sale rate with Forever's modern auction API.

- Removed: the Shopping *Sale Rate* column, the "Sale Rate (TSM)" tooltip row, the "Minimum sale rate" setting with its bag-glow gate and `minSaleRate` default, and `AP.TSM.SalePercentFor`, `SaleRateText` and `SALE_RATE_SOURCE`. Guide, README and settings text no longer mention it.
- Kept: Average Price (TSM), Relative Value (TSM) and "Require both values". They stay hidden (or have no effect) while `TSM_API` is nil.
- The last code with sale rate is `1e3f8d3` (`Modules/TSM.lua`, `TrendColumn.lua`, `BagGlow.lua`, `PriceHistory.lua`, `UI/Settings.lua`).
- A re-implementation must fix AP-3 first: TSM rounds a 0–1 fraction to 0 (nil) or 1. Ask TSM for a scaled value (syntax UNVERIFIED) or use a TSM API that returns the raw rate.
- Existing saved variables may still hold a `minSaleRate` key. Nothing reads it, and no migration removes it.

## Audit 2026-09-30: status after 4.0.0

Done in round 2 (owner decisions, still 4.0.0):

| ID | What was done |
|---|---|
| AP-2 | Plus Full Scan reads Auctionator's `REPLICATE_SCAN` at click time: on, `FullScanFrameRef:InitiateScan()` (replicate); off, the default, `IncrementalScanFrameRef:InitiateScan()`. That is exactly Auctionator's `ScanButton.lua:3-8`. The label follows the ScanStart/Progress/Complete/Failed events of both `FullScan.Events` and `IncrementalScan.Events`. The tooltip names the mode, with a "one scan every 15 minutes" line only in replicate mode. Lead's follow-up: in incremental mode (the default), while `AuctionatorShoppingFrame.searchRunning`, a click on either Plus Full Scan does nothing and the tooltip shows a red `GameTooltip_AddErrorLine`. This mirrors Sale Scan's slotted-item refusal (`hasSaleItem`/`addSlottedWarning` through `AP.Panel.CreateTabButton`'s tooltip hook). In replicate mode the scan starts as normal with no red line, because `ReplicateItems` reads its own list and not the browse result set |
| AP-3 | Resolved by removing sale rate (see "Sale rate" above) |
| AP-4 | Decided: the sale-rate parts are removed. The TSM market-value parts stay as they are, hidden until TSM ships for Forever |
| AP-18 | Decided: the sale-slot icon keeps its glow (no code change) |
| Similar retry | A Similar browse that was skipped because a shopping search or incremental scan was running now waits instead. So does one that gave way mid-paging when such a search or scan started. It runs once `Shopping.Tab.Events.SearchEnd` or `IncrementalScan.Events.ScanComplete`/`ScanFailed` fires. The check runs a frame later, since `DoSearch` ends the old shopping search just before it starts the next. It needs no shopping search or incremental scan running and `AuctionatorSellingFrame:IsVisible()`. Leaving the tab (its `OnHide`), clearing the slot and every new sell search drop the waiting profile, so a retry only ever runs for the item still selected. Another selection runs its own flow |
| Colours/chat | Nothing to change (see Native UI above) |

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

Still open, blocked on the owner:

| ID | Severity | Finding | Options |
|---|---|---|---|
| AP-15 | Low | No `## AddonCompartmentFunc` | Add one that opens settings |

Open questions:

- No slash command exists. Settings open only from the Auctionator tab button and the Guide. Adding `/ap` means one `SlashCmdList` entry in `UI/Settings.lua` calling `AP.SettingsPanel.Open`.
- Resolved in round 2 (lead): the Shopping tab's Plus Full Scan would have started the incremental browse scan during a running shopping search. Auctionator's own button never meets that case, since leaving the Shopping tab stops the search. Both then page the one browse result set, because `Auctionator.AH.Queue` only throttles (`Source_ModernAH/AH/Wrappers.lua:47-58`). In incremental mode the button now refuses while a search runs; replicate mode is unaffected (AP-2 row above).

## Blockers, issues, challenges

1. The addon depends on about 20 unguarded Auctionator 339 internals (listed above). A renamed function or mixin in Auctionator aborts a whole file.
2. The TSM market-value rows stay off on Forever until TSM ships a 16001 build. Sale rate is removed until then.
3. Forever item stat wording can't be verified offline. Whether Forever browse item keys carry the random-suffix id is unknown.
4. The Similar browse still reacts to other addons' or Blizzard's own browse queries, which Auctionator doesn't announce.

## Next steps

1. Owner decisions: AP-15 and the slash command.
2. Push `main` once the in-game checks below pass.
3. Enable only Auctionator and AuctionatorPlus, then run `/console scriptErrors 1` and `/reload`.

Forever checks:

- [ ] The AddOns list shows Auctionator Plus 4.0.0 under Auctions, not out of date.
- [ ] No errors at login or on the first AH open.
- [ ] A bag item and a chat link show the Auctionator average and Relative Value, in white rows after a blank line.
- [ ] Shopping: *Relative* sorts with blanks last, and there is no *Sale Rate* column. Full Scan, Filter and Reset sit on the Export row.
- [ ] Selling, Show Similar Items: left-click takes the exact price, right-click does nothing, shift links, ctrl previews. Show Similar Bags matches slot count.
- [ ] Sale Scan counts, cancels and stops on item select. With an item slotted, a click does nothing and the tooltip shows the red line.
- [ ] AP-2, default mode: Plus Full Scan prints Auctionator's "Starting a full scan (summary mode).", counts up to green on both Plus buttons and on Auctionator's own status, and a click during the scan prints "Full scan in progress.". Tooltip without the 15-minute line.
- [ ] AP-2 refusal, default mode: start a shopping list search, then hover and click Plus Full Scan while it runs. Nothing starts, and the tooltip shows the red "Wait for the shopping search to finish first." line. After the search ends, the line is gone and a click starts the scan.
- [ ] AP-2 refusal, Alternate Scan Mode on: during a shopping search the tooltip has no red line and a click starts the replicate scan. Shopping results stay complete.
- [ ] AP-2, Auctionator's Advanced "Alternate Scan Mode" on: it prints "(replicate mode)", goes green, and a second click gives Auctionator's cooldown message. Tooltip shows the 15-minute line.
- [ ] Settings page: no "Minimum sale rate" slider. Tooltips show no "Sale Rate (TSM)" row.
- [ ] Settings persist across `/reload`. A fresh WTF shows the defaults before the settings panel is opened.
- [ ] The Guide and the Stat Filter show the DiamondMetal border and header, with the close button in the corner and text 20 px from the edges. Escape closes both.
- [ ] `/dump TSM_API` prints nil, and no TSM rows show.
- [ ] Stat Filter shows 25 stats, none clipped.
- [ ] AP-1 and the retry: start the incremental Full Scan on the Selling tab, then slot gear with Show Similar Items on. No comparables appear while it runs, the scan finishes normally, then the comparables appear. Slot gear, then switch to Shopping and search at once: shopping results are complete.
- [ ] Retry negatives: start a scan, slot gear, then switch tabs or clear the slot before it ends. Nothing merges later. Slot another item during the scan: its own comparables come after the scan.
- [ ] `/dump C_AuctionHouse.GetBrowseResults()[1].itemKey` on an "of the X" item: is the suffix id present?
- [ ] `/dump WOW_PROJECT_ID`.
- [ ] Record the stat wording: `/run local t=C_TooltipInfo.GetHyperlink(select(2,C_Item.GetItemInfo(<id>))) for _,l in ipairs(t.lines) do print(l.leftText) end`.
