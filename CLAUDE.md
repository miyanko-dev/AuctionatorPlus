# AuctionatorPlus

## Target

- WoW Forever 1.60.x only, `## Interface: 16001`. No client branches, no `WOW_PROJECT_*`, no compat layer.
- `main` holds the Forever version. `1.15.x-backup` keeps the dual-client 3.0.0 with all Classic code and stays untouched.
- Verify every API against Gethe `wow-ui-source` and Ketho `BlizzardInterfaceResources`, branch `forever`, using only the files the Forever client loads.
- Verify Auctionator internals against its mainline/camelot load set: `Source/`, `Source_Mainline/`, `Source_ModernAH/` and `Source_Forever/`.

## Rules

- `Modules/` holds one file per feature. A feature module owns its Auctionator hooks and the widgets it places in Auctionator's frames. `UI/` holds only `Panel.lua`, `Guide.lua` and `Settings.lua`.
- `UI/Panel.lua` loads before `ShoppingFilter`, which reads `AP.Panel.INSET` at load. `Bootstrap` builds its list from every module at load, so it stays last.
- Auctionator's shopping search, its incremental scan and the Similar browse share one browse result set, since `Auctionator.AH.Queue` only throttles (`Source_ModernAH/AH/Wrappers.lua`). Two of them must never run at once. The replicate scan reads its own list and is exempt.
- The stat parser matches the client's own `ITEM_MOD_*` and `_SHORT` strings in long and short form, `%d` included, and skips inactive `(2) Set:` lines. The Stat Filter always lists all 25 stats and drops saved keys it does not list.
- Sale Scan records the cheapest buyout, not the first result's `buyoutAmount or bidAmount` that Auctionator's own sell search records.
- TSM is read only through `TSM_API`, and only `DBMarket`. `GetCustomPriceValue` rounds to a whole number and turns 0 into nil, so a 0 to 1 source such as `DBRegionSaleRate` comes back as nil or 1.
- Sale rate stays out until TradeSkillMaster ships a full Forever build and it is known whether TSM can give sale rate with Forever's auction API.
- The sale slot icon keeps its glow on purpose.
- `/ap` stays unused: Blizzard's commentator commands own it (`SLASH_COMMENTATOR_ASSIGNPLAYER3`).
- Dialogs come from `UI/Panel.lua`: Blizzard's DiamondMetal dialog with `DialogBorderTemplate` and `DialogHeaderTemplate`, content 40 px below the top and 20 px from the sides and bottom.
- Buttons inside Auctionator's frames match their neighbours. Full Scan and Sale Scan are fixed 110x22 `UIPanelButtonTemplate`, since their labels change during a scan. Filter, Reset and the options button are `UIPanelDynamicResizeButtonTemplate`, like Auctionator's Export Results and Open Addon Options.
- Text uses Blizzard font objects only. Colours come from Blizzard colour objects such as `GREEN_FONT_COLOR`, `RED_FONT_COLOR` and `HIGHLIGHT_FONT_COLOR`, never literal `|cff` codes.
- The addon prints no chat lines. The lines during a Plus Full Scan are Auctionator's own. A line added later starts with `YELLOW_FONT_COLOR:WrapTextInColorCode("[Auctionator Plus]:") .. " "`.

## Checks

- Run `luac -p` on every Lua file after a change. The repo has no test harness.
- Test in game with only Auctionator and AuctionatorPlus enabled, after `/console scriptErrors 1` and `/reload`.
