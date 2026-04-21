# FlipFinder

A companion add-on for [Auctionator](https://www.curseforge.com/wow/addons/auctionator) that adds a **FlipFinder** button to the shopping tab. Click it to open a panel displaying potential flip deals with configurable filters.

## How it works

After you run a shopping-list search, the add-on caches the matched entries. When you click **Scan for Flips**, it walks each cached item's live listings and finds price brackets where the cheapest listing is at least 20% lower than the next bracket price. It then displays all found flips in a panel with the following information:

- **Item Name** — the item being flipped
- **Quantity** — total units available at the flip price
- **Invest** — total gold required to buy all flip listings
- **Profit** — estimated profit after auction house cut

## Features

- **FlipFinder** button added next to the shopping tab's *Export Results* button.
- Interactive results panel with sortable flip deals.
- Configurable filters:
  - **Min. Quantity** — minimum total quantity required for a flip to be shown
  - **Max. Invest** — maximum gold you're willing to invest in a single flip
  - **Min. Price Margin (in %)** — minimum percentage price jump to flag a deal
- Search button per row to quickly look up the item.
- Works for both commodity and non-commodity auctions; non-commodity prices are normalised to unit price.
- Scans pause automatically when you click into an item to buy it.
- Per-item scan timeout prevents the queue from stalling on unresponsive queries.

## Usage

1. Open the Auction House and switch to the **Shopping** tab.
2. Run a shopping-list search as normal.
3. Click **FlipFinder** (to the left of *Export Results*).
4. Adjust filters as needed and click **Scan for Flips**.
5. Click **Search** on any row to look up that item in Auctionator.

## Configuration

Three thresholds are configurable via the panel filters:

| Filter | Description | Default |
|--------|-------------|---------|
| Min. Quantity | Minimum total quantity at flip price | 1 |
| Max. Invest | Maximum gold to invest (in gold, not copper) | 200000 |
| Min. Price Margin | Minimum % price jump between brackets | 20% |

The internal price jump ratio is defined at the top of `FlipFinder.lua`:

```lua
local PRICE_JUMP_RATIO = 1.20   -- 20% minimum spread
```

## Dependencies

- [Auctionator](https://www.curseforge.com/wow/addons/auctionator) (required, declared in the TOC).

## Interface

Built and tested against WoW Retail / Midnight (Interface 120001).
