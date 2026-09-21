# AuctionatorPlus

A companion for [Auctionator](https://www.curseforge.com/wow/addons/auctionator) that adds price history, gear comparison and stat filtering to the Auction House.

## Features

- **Price-history tooltips** — item tooltips show the Auctionator 14-day average price and the TSM price, each tagged with its data age, plus the item's relative value against them and the TSM sale rate
- **Relative Value column** — shopping results and current-prices listings gain a *Relative* column, green when the price is favourable, so underpriced deals stand out
- **Show Similar Items** — drop a piece of gear in the sale slot and a background search finds auctions for the same slot and armor or weapon type, at a similar required level, carrying the same stats within a tolerance you set. Weapons must also land in a DPS range.
- **Show Similar Bags** — the same checkbox for containers, listing every bag with the same slot count regardless of bag type
- **Price from comparables** — hover a result to preview the item, click its row to take over its exact unit price for your own listing
- **Filter by Stat** — a *Filter* button in the shopping tab gates results by primary stats, attack power, spell power by school, healing, hit, crit, defense and mana per 5 sec, with match-all or match-any. Only equipment is constrained, so consumable searches never come back empty.
- **Green bag glow** — items in the Selling tab's bag panel whose last known price beats the averages by your threshold (default +15%) get a green glow over their icon
- **Full Scan** — a button in both the shopping and Selling tabs starts Auctionator's full scan, with a live progress readout
- **Sale Scan** — runs a live price search for every distinct item in your bag panel, so the Relative column and the glow reflect current prices instead of your last full scan
- **Sale Rate** — the TSM region-wide share of auctions that actually sell, as a column, a tooltip row, and an optional gate so slow sellers never glow
- **Guide** — a short list of what the addon adds, shown once per character at login

## Installation

1. Copy the `AuctionatorPlus/` folder into `World of Warcraft/_classic_era_/Interface/AddOns/`.
2. Restart the game or `/reload`.
3. Enable **Auctionator Plus** in the AddOns list.

## Usage

1. In the Selling tab, drop a gear item or bag in the sale slot and tick **Show Similar Items** or **Show Similar Bags**. Comparable auctions appear in the current-prices list automatically, without switching tabs.
2. Hover any item to see its price history.
3. Sort shopping results by the **Relative** column to surface underpriced items.
4. Click a comparable's row to adopt its unit price.

## Settings

The **Auctionator Plus Options** button on Auctionator's own tab opens the panel: bag-glow sell threshold, whether both relative values must reach it, minimum sale rate, and the level, weapon DPS, stat value and stat count ranges used for similar items.

## Requirements

- WoW Classic Era / Anniversary 1.15.x
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator) — a hard dependency
- TSM rows are optional: they need the TradeSkillMaster_AppHelper addon and the TSM desktop application running. Without app data those rows stay hidden.

## Restrictions

Price history comes from the data Auctionator already collected, so run a **Full Scan** or a **Sale Scan** before trusting the Relative column. Fresh TSM app data is picked up on login or `/reload`.
