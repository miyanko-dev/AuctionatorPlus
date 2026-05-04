# Auctionator Flip Finder

A companion add-on for [Auctionator](https://www.curseforge.com/wow/addons/auctionator) that adds a **Flipper** button to the shopping tab. Click it to open a panel displaying potential flip deals with configurable filters.

## How it works

After you run a shopping-list search, the add-on caches the matched entries. When you click **Scan for Flips**, it walks each cached item's live listings, sorts them ascending by unit price, and flags the first consecutive price gap that meets or exceeds the configured minimum margin. All listings below that gap form the cheap bracket; the next listing's price is the resale target. Results are shown with:

- **Item Name** — the item being flipped
- **Listed Qty** — total units currently listed for that item
- **Order Qty** — how many units you would buy from the cheap bracket
- **Invest** — total gold required to buy all cheap-bracket listings
- **Profit** — estimated profit after the 5% auction house cut

Tweaking filters after a scan re-applies them against the cached listings via **Apply Filter** — no rescan needed.

## Features

- **Flipper** button added next to the shopping tab's *Export Results* button.
- Interactive results panel sorted by ascending invest.
- Configurable filters:
  - **Min. Total Qty** — minimum total listed quantity for an item to be considered
  - **Max. Order Qty** — maximum units the flip can require you to buy
  - **Max. Qty %** — maximum share (%) of the total listed stock the flip would consume
  - **Max. Invest** — maximum gold you're willing to spend on a single flip (in gold)
  - **Min. Profit** — minimum post-cut profit in gold
  - **Min. Margin** — minimum percentage price gap between consecutive listings
- **Apply Filter** re-filters cached listings without a rescan; a green "Filter applied" confirmation fades in for 4 seconds.
- Status row shows `Scanning: X/Y` during a scan and `Ready` when idle.
- In-table helper text before the first scan, with an adjust-filters suggestion when a scan returns no results.
- Search button per row to quickly look up the item in Auctionator.
- Works for both commodity and non-commodity auctions; non-commodity prices are normalised to unit price.
- Scans pause automatically when you click into an item to buy it.
- Per-item scan timeout prevents the queue from stalling on unresponsive queries.

## Usage

1. Open the Auction House and switch to the **Shopping** tab.
2. Run a shopping-list search as normal.
3. Click **Flipper** (to the left of *Export Results*).
4. Adjust filters as needed and click **Scan for Flips**.
5. After the scan, tweak filters and click **Apply Filter** to refine the list without rescanning.
6. Click **Search** on any row to look up that item in Auctionator.

## Configuration

| Filter | Description | Default |
|--------|-------------|---------|
| Min. Total Qty | Minimum total listed quantity | 1 |
| Max. Order Qty | Maximum units bought in a flip | off |
| Max. Qty % | Maximum % of listed stock the flip consumes | off |
| Max. Invest | Maximum gold to invest (in gold) | off |
| Min. Profit | Minimum post-cut profit (in gold) | off |
| Min. Margin | Minimum % price gap between consecutive listings | 10% |

Empty / 0 disables a filter, except `Min. Total Qty` (falls back to 1) and `Min. Margin` (falls back to the default).

The default margin is defined at the top of `Flipper.lua`:

```lua
local PRICE_JUMP_RATIO = 1.10   -- 10% minimum price gap
```

## Dependencies

- [Auctionator](https://www.curseforge.com/wow/addons/auctionator) (required, declared in the TOC).

## Interface

Built and tested against WoW Retail / Midnight (Interface 120005).
