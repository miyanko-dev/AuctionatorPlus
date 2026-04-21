# Auctionator Arbitrage Finder

A companion add-on for [Auctionator](https://www.curseforge.com/wow/addons/auctionator) that announces arbitrage opportunities in your shopping-list searches — items whose cheapest listings reveal a meaningful price jump, so you can buy low and relist higher.

It works purely on the live auction house data returned by your current shopping-list search. No historical database, no external API — just real-time price brackets.

## How it works

After Auctionator finishes a shopping-list search, this add-on scans each matching item's live listings, extracts the distinct price brackets (ignoring how many stacks or units exist in each bracket), and compares the cheapest bracket against the fifth-cheapest bracket.

If the ratio between them is at least 10%, a chat message announces the deal — including the item link, cheapest and dearest bracket prices, the ratio, and how many brackets were considered.

Scans pause automatically when you click into an item to buy it, so the add-on never fights Auctionator's own auction-house queries for priority.

## Features

- Live per-item bracket scan after every shopping-list search.
- Chat notification with item link, cheapest and dearest bracket, price ratio, and bracket count.
- Focuses on the **first 5 distinct price brackets** to keep potential capital outlay manageable — a cheap bracket with 10,000 listings no longer inflates the scan window.
- Requires at least a **10% spread** between the cheapest and fifth-cheapest bracket to flag a deal.
- Works for both commodity and non-commodity auctions; non-commodity prices are normalised to unit price.
- Yields immediately to user clicks on an item, so buy flows are never blocked.
- Per-item scan timeout prevents the queue from stalling on unresponsive queries.

## Slash commands

- `/caf` — print the add-on's state (registered, scanning, cached entries, detected deals).
- `/caf list` — list every detected arbitrage opportunity with prices and ratio.
- `/caf rescan` — re-scan the cached shopping-list entries without having to re-run the search.

## Configuration

Two thresholds are defined at the top of `AuctionatorArbitrageFinder.lua`:

```lua
local PRICE_JUMP_RATIO = 1.10   -- 10% minimum spread
local MAX_BRACKETS = 5          -- first 5 distinct price brackets
```

Edit them in place to tighten or loosen the detection.

## Dependencies

- [Auctionator](https://www.curseforge.com/wow/addons/auctionator) (required, declared in the TOC).

## Interface

Built and tested against WoW Retail / Midnight (Interface 120001).
