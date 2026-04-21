# FlipFinder

A companion add-on for [Auctionator](https://www.curseforge.com/wow/addons/auctionator) that adds a **Scan for Flips** button to the shopping tab. Click it to find items whose cheapest listings reveal a meaningful price jump, so you can buy low and relist higher.

It works purely on the live auction house data returned by your current shopping-list search. No historical database, no external API — just real-time price brackets.

## How it works

After you run a shopping-list search, the add-on caches the matched entries. When you click **Scan for Flips** (placed to the left of Auctionator's **Export Results** button), it walks each cached item's live listings, extracts the distinct price brackets (ignoring how many stacks or units exist in each bracket), and compares the cheapest bracket against the fifth-cheapest bracket.

If the ratio between them is at least 10%, a chat message announces the deal — including the item link, cheapest and dearest bracket prices, the ratio, and how many brackets were considered.

Scans pause automatically when you click into an item to buy it, so the add-on never fights Auctionator's own auction-house queries for priority.

## Features

- **Scan for Flips** button added next to the shopping tab's *Export Results* button.
- Chat notification per detected deal: item link, cheapest and dearest bracket, price ratio, and bracket count.
- Focuses on the **first 5 distinct price brackets** to keep potential capital outlay manageable — a cheap bracket with 10,000 listings no longer inflates the scan window.
- Requires at least a **10% spread** between the cheapest and fifth-cheapest bracket to flag a deal.
- Works for both commodity and non-commodity auctions; non-commodity prices are normalised to unit price.
- Yields immediately to user clicks on an item, so buy flows are never blocked.
- Per-item scan timeout prevents the queue from stalling on unresponsive queries.

## Usage

1. Open the Auction House and switch to the **Shopping** tab.
2. Run a shopping-list search as normal.
3. Click **Scan for Flips** (to the left of *Export Results*).
4. Watch chat for `[FlipFinder] Deal found: ...` messages.

## Configuration

Two thresholds are defined at the top of `FlipFinder.lua`:

```lua
local PRICE_JUMP_RATIO = 1.10   -- 10% minimum spread
local MAX_BRACKETS = 5          -- first 5 distinct price brackets
```

Edit them in place to tighten or loosen the detection.

## Dependencies

- [Auctionator](https://www.curseforge.com/wow/addons/auctionator) (required, declared in the TOC).

## Interface

Built and tested against WoW Retail / Midnight (Interface 120001).
