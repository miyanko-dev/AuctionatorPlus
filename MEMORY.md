# AuctionatorPlus — Memory

Updated 2026-09-25 after the dual-client port with native UI (decision: every addon in the folder supports both clients, with each client's own look). Verified against Gethe `forever` @ `bd2470a` (1.60.1.70009), Gethe `classic_era` @ `33e177d` (1.15.9.69722), the matching Ketho dumps, and the installed Auctionator 339 and TradeSkillMaster v4.14.77. Nothing has run in a client. Offline checks, all in that session's scratchpad `ap_harness/`:

- the stat parser passes 93/93 against each client's own strings
- a stubbed load of both clients' file sets runs clean
- a simulated Era Show Similar Items flow behaves as intended

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
| Version | 3.0.0, both clients from one toc, `## Interface: 11509, 16001`, `## Author: miyanko`, `## Dependencies: Auctionator`, `## OptionalDeps: TradeSkillMaster` |
| Git | Committed and pushed on 2026-09-25: `main` = `origin/main`. `1.15.x-backup` = `6cb650a` (2.0.0, Era only, the last pre-port release) is pushed too |

Layout:

- Shared modules sit in `Modules/`.
- Client halves sit in `Modules/Era/` and `Modules/Forever/`, gated per toc line with `[AllowLoadGameType vanilla]` and `[AllowLoadGameType mainline]`, exactly as `../Auctionator/Auctionator.toc:42-51` does.
- Each half exposes the same function names, so shared code never branches.

| Area | Era half | Forever half |
|---|---|---|
| Bridge | Legacy AH: `QueryAuctionItems`, scanner, `HistoricalPrice` | Modern AH: item keys, browse, item search, `PriceSelected` |
| Stat text source | Hidden scan tooltip | `C_TooltipInfo` |
| Tooltips | GameTooltip method hooks | `TooltipDataProcessor` |
| Trend columns | Legacy Shopping + BuyAuctions providers | Modern Shopping, search, buy-item providers |
| Similar items | 2.0.0 SellingWatch port, with the click-path fix | 3.0.0 browse and merge |
| Full Scan, Sale Scan | 2.0.0 placement and name scan | 3.0.0 |

Shared across both clients:

- Stat parser: matches each client's own `ITEM_MOD_*` / `_SHORT` strings in long and short form. It now parses `%d` too (Era prints `"%c%d Agility"`) and skips inactive `(2) Set:` lines. The Shopping filter offers 21 stats on Era and 25 on Forever (haste, expertise, piercing).
- TSM: `TSM_API` on both clients, replacing 2.0.0's `TSMFeed`. TSM loads on Era and is absent on Forever.
- The 2.0.0 `tsmHint` → `guideAtLogin` migration is back.
- Native UI: dialogs are Era `BackdropTemplate` + `BACKDROP_DIALOG_32_32` + `ClassicDialogHeaderTemplate`, or Forever `DialogBorderTemplate` + `DialogHeaderTemplate`, picked by `C_XMLUtil.GetTemplateInfo`. Text uses Blizzard font objects only. Settings use the Blizzard vertical layout.

## Blockers, issues, challenges

1. The addon depends on about 20 unguarded Auctionator 339 internals per client (listed in the 2026-09-25 port report). A rename in Auctionator aborts a whole file.
2. The TSM features are off on Forever until TSM ships a 16001 build. On Era, the TSM tooltip row loses its data-age suffix, because `TSM_API` has no age accessor.
3. That the 1.15.9 toc parser honours per-line gates is inferred from Auctionator, which relies on it.
4. On Forever, the Similar Items browse may pick up other browse results (unverified). Forever item stat wording is unverifiable, and `C_AuctionHouse.SupportsCopperValues()` is unknown.
5. There's no `_classic_era_` install. The installed beta is 69913, the source is 70009.

## Next steps

1. Enable only Auctionator and AuctionatorPlus (and optionally TSM on Era), then run `/console scriptErrors 1` and `/reload`.

Both clients:

- [ ] No errors at login or on the first AH open. That proves the toc gating and the mixin patches.
- [ ] A bag item and a chat link show the Auctionator average and Relative Value.
- [ ] Shopping: *Relative* and *Sale Rate* sort with blanks last. Full Scan, Filter and Reset sit on the Export row.
- [ ] Selling, Show Similar Items: left-click takes the exact price, right-click does nothing, shift links, ctrl previews. Show Similar Bags matches slot count.
- [ ] Sale Scan counts, cancels and stops on item select. Full Scan goes green, and a second click gives Auctionator's cooldown message.
- [ ] Settings persist across `/reload`.

Era:

- [ ] The Guide shows the UI-DialogBox border and classic header.
- [ ] Stat Filter shows 21 stats, with no Haste, Expertise or Penetration.
- [ ] TSM rows appear when TSM has data.
- [ ] With Auctionator's "ignore item suffix" on, suffix variants aren't injected twice.

Forever:

- [ ] The Guide shows the DiamondMetal border and header.
- [ ] `/dump TSM_API` prints nil, and no TSM rows show.
- [ ] Stat Filter shows 25 stats, none clipped.
- [ ] Shopping results survive a Similar Items browse. That settles issue 4.
- [ ] Record `/dump C_AuctionHouse.SupportsCopperValues()`.
- [ ] Record the stat wording: `/run local t=C_TooltipInfo.GetHyperlink(select(2,C_Item.GetItemInfo(<id>))) for _,l in ipairs(t.lines) do print(l.leftText) end`.
