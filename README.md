# AuctionatorPlus

A companion for [Auctionator](https://www.curseforge.com/wow/addons/auctionator) that adds price history, gear comparison and stat filtering to the Auction House. One addon folder runs on both WoW Classic Era 1.15.x and WoW Forever 1.60.x.

## Features

- **Price-history tooltips** — item tooltips show the Auctionator 14-day average price and the TSM market value, plus the item's relative value against them and the TSM sale rate
- **Relative Value column** — shopping results, the shopping buy screen and the Selling tab's current prices gain a *Relative* column, green when the price is favourable, so underpriced deals stand out
- **Show Similar Items** — select a piece of gear to sell and a background search finds auctions of items with the same slot and armor or weapon type, at a similar required level, carrying the same stats within a tolerance you set. Weapons must also land in a DPS range.
- **Show Similar Bags** — the same checkbox for containers, listing bags with the same slot count
- **Price from comparables** — hover a comparable row to preview the item, click it to take over its exact unit price for your own listing
- **Filter by Stat** — a *Filter* button in the shopping tab gates results by primary stats, attack power, hit, critical strike, defense, spell power (also by school), spell healing, spell hit and crit and mana regeneration, with match-all or match-any. On WoW Forever it also offers haste, expertise, armor piercing and spell piercing. Only equipment is constrained, so consumable searches never come back empty.
- **Green bag glow** — items in the Selling tab's bag panel whose last known price beats the averages by your threshold (default +15%) get a green glow over their icon
- **Full Scan** — a button in both the shopping and Selling tabs starts Auctionator's full scan, with a live progress readout
- **Sale Scan** — runs a live price search for every distinct item in your bag panel, so the Relative column and the glow reflect current prices instead of your last full scan
- **Sale Rate** — the TSM region-wide share of auctions that actually sell, as a column, a tooltip row, and an optional gate so slow sellers never glow
- **Guide** — a short list of what the addon adds, shown once per character at login

## Installation

Copy the `AuctionatorPlus/` folder into the `Interface/AddOns/` folder of the client you play:

| Client | Folder |
|---|---|
| WoW Classic Era / Anniversary 1.15.x | `World of Warcraft/_classic_era_/Interface/AddOns/` |
| WoW Forever 1.60.x | `World of Warcraft/_classic_beta_/Interface/AddOns/` |

Then restart the game or `/reload`, and enable **Auctionator Plus** in the AddOns list. The same folder works in both; each client loads only the files meant for it.

## Usage

1. In the Selling tab, select a gear item or bag and tick **Show Similar Items** or **Show Similar Bags** next to the bag panel. Comparable auctions appear in the current-prices list automatically, without switching tabs.
2. Hover any item to see its price history.
3. Sort shopping results by the **Relative** column to surface underpriced items.
4. Click a comparable's row to adopt its unit price.

## Settings

The **Auctionator Plus Options** button on Auctionator's own tab opens the panel under Options > AddOns: bag-glow sell threshold, whether both relative values must reach it, minimum sale rate, and the level, weapon DPS, stat value and stat count ranges used for similar items.

## Requirements

- WoW Classic Era / Anniversary 1.15.x, or WoW Forever 1.60.x
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator) — a hard dependency, the build for your client
- TSM rows are optional: they need TradeSkillMaster with AuctionDB data for your realm, which comes from the TSM desktop app through TradeSkillMaster_AppHelper. TSM loads on Classic Era today. It has no WoW Forever build yet, so on Forever the TSM rows stay hidden until it ships one.

## Restrictions

Price history comes from the data Auctionator already collected, so run a **Full Scan** or a **Sale Scan** before trusting the Relative column.
