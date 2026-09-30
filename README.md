# AuctionatorPlus

A companion for [Auctionator](https://www.curseforge.com/wow/addons/auctionator) that adds price history, gear comparison and stat filtering to the Auction House in WoW Forever 1.60.x.

## Features

- **Price-history tooltips** — item tooltips show the Auctionator 14-day average price and the TSM market value, plus the item's relative value against them
- **Relative Value column** — shopping results, the shopping buy screen and the Selling tab's current prices gain a *Relative* column, green when the price is favourable, so underpriced deals stand out
- **Show Similar Items** — select a piece of gear to sell and a background search finds auctions of items with the same slot and armor or weapon type, at a similar required level, carrying the same stats within a tolerance you set. Weapons must also land in a DPS range. The search waits while Auctionator's own shopping search or full scan runs, gives way when one starts, and runs once it ends while the Selling tab is still open with the same item selected.
- **Show Similar Bags** — the same checkbox for containers, listing bags with the same slot count
- **Price from comparables** — hover a comparable row to preview the item, click it to take over its exact unit price for your own listing
- **Filter by Stat** — a *Filter* button in the shopping tab gates results by primary stats, attack power, hit, critical strike, haste, expertise, armor piercing, defense, spell power (also by school), spell healing, spell hit, spell crit, spell piercing and mana regeneration, with match-all or match-any. Only equipment is constrained, so consumable searches never come back empty.
- **Green bag glow** — items in the Selling tab's bag panel whose last known price beats the averages by your threshold (default +15%) get a green glow over their icon
- **Full Scan** — a button in both the shopping and Selling tabs starts Auctionator's full scan in the scan mode set in Auctionator's options, like Auctionator's own Full Scan button, with a live progress readout for either mode. In Auctionator's default scan mode it doesn't start while a shopping search runs, since both would use the same auction list; in Alternate Scan Mode it starts as normal.
- **Sale Scan** — runs a live price search for every distinct item in your bag panel, so the Relative column and the glow reflect current prices instead of your last full scan. It needs an empty sale slot.
- **Guide** — a short list of what the addon adds, shown once per character at login

## Installation

Copy the `AuctionatorPlus/` folder into `World of Warcraft/_classic_beta_/Interface/AddOns/`, then restart the game or `/reload`, and enable **Auctionator Plus** in the AddOns list.

## Usage

1. In the Selling tab, select a gear item or bag and tick **Show Similar Items** or **Show Similar Bags** next to the bag panel. Comparable auctions appear in the current-prices list automatically, without switching tabs.
2. Hover any item to see its price history.
3. Sort shopping results by the **Relative** column to surface underpriced items.
4. Click a comparable's row to adopt its unit price.

## Settings

Type `/aplus` (or `/auctionatorplus`), pick **Auctionator Plus** in the addon menu at the minimap, or press the **Auctionator Plus Options** button on Auctionator's own tab. All three open the panel under Options > AddOns: bag-glow sell threshold, whether both relative values must reach it, and the level, weapon DPS, stat value and stat count ranges used for similar items.

## Requirements

- WoW Forever 1.60.x
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator) — a hard dependency
- TSM rows are optional: they need TradeSkillMaster with AuctionDB data for your realm, which comes from the TSM desktop app through TradeSkillMaster_AppHelper. TSM has no WoW Forever build yet, so the TSM rows stay hidden until it ships one.

## Restrictions

Price history comes from the data Auctionator already collected, so run a **Full Scan** or a **Sale Scan** before trusting the Relative column.
