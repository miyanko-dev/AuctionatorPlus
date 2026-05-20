# Auctionator Flip Finder

A companion add-on for [Auctionator](https://www.curseforge.com/wow/addons/auctionator) that adds a **Flipper** button to the Shopping tab. Click it to open a panel — docked to the right of the Auction House — that surfaces items whose lowest auctions span a price gap above the configured margin.

Works on **WoW Retail (Midnight, Interface 120005)** and **WoW Classic Era 1.15.x (Interface 11508)** from a single TOC.

## How it works

After you run a shopping search in Auctionator, the add-on captures the matched entries. When you click **Find Flips**, it gathers every listing for each item, sorts them ascending by unit price, and flags the first consecutive price gap that meets or exceeds the configured minimum margin. All listings below that gap form the cheap bracket; the next listing's price is the resale target. Each row shows:

- **Item Name** — the item being flipped (hover for tooltip, modified right-click to chat-link)
- **Listed Qty** — total units currently listed for that item
- **Order Qty** — how many units you would buy from the cheap bracket
- **Invest** — total gold required to buy all cheap-bracket listings
- **Profit** — estimated profit after the AH cut

Editing any filter after a scan re-applies the filter set against the cached listings — no rescan needed.

Click a flip row to inspect that item:

- Retail: opens a new Auctionator search for the item (via `Auctionator.API.v1.MultiSearchExact`).
- Classic: opens Auctionator's built-in Buying view for that item (via the `ShowForShopping` event).

## Folder layout

```
AuctionatorFlipFinder/
├── AuctionatorFlipFinder.toc        # Single TOC, multi-Interface
├── README.md
├── Core/                             # Loaded on every WoW version
│   ├── Manifest.xml
│   ├── Init.lua                      # FF namespace + defaults
│   ├── Constants.lua                 # Sort options, layout dimensions
│   ├── Format.lua                    # Money / item-text formatting
│   ├── Bracket.lua                   # Price-gap detection (pure)
│   ├── Filters.lua                   # Filter commit + flip-build
│   ├── Scanner.lua                   # Orchestrator (drives the Adapter)
│   ├── Panel.lua                     # Full panel UI
│   └── Bootstrap.lua                 # Events + toggle button
├── Retail/                           # Loaded on mainline only
│   ├── Manifest.xml
│   └── Adapter.lua                   # C_AuctionHouse scan loop + retail UI
└── Classic/                          # Loaded on vanilla only
    ├── Manifest.xml
    └── Adapter.lua                   # Cached-entries reader + classic UI
```

`Core/` builds the panel and orchestrates the flow. Each version's `Adapter.lua` plugs in the version-specific pieces:

- `FF.Adapter.GetAnchorButton()` — where to anchor the Flipper toggle button
- `FF.Adapter.CreateDropdown(parent, width, options, getKey, setKey)` — native dropdown widget
- `FF.Adapter.RegisterEventBus()` — subscribes to Auctionator's Shopping/AH events
- `FF.Adapter.ScanEntries(entries, onListings, onComplete)` — produces listings per entry
- `FF.Adapter.AbortScan()` — cancels an in-flight scan
- `FF.Adapter.OpenFlipDetails(flip)` — inspects a flip in Auctionator

TOC routing is via `AllowLoadGameType`:

```
Core\Manifest.xml
Retail\Manifest.xml [AllowLoadGameType mainline]
Classic\Manifest.xml [AllowLoadGameType vanilla]
```

## Usage

1. Open the Auction House and switch to the **Shopping** tab.
2. Run a shopping-list search as normal.
3. Click **Flipper** (to the left of *Export Results*).
4. Adjust filters as needed and click **Find Flips**.
5. Tweak filters after the scan to refine the list without rescanning.
6. Click any row to inspect that item.

## Filters

| Filter | Description | Default |
|---|---|---|
| Min Listed Qty | Minimum total listed quantity | 1 |
| Max Order Qty | Maximum units bought in a flip | off |
| Max Order Qty % | Maximum % of listed stock the flip consumes | off |
| Max Invest | Maximum gold to invest | off |
| Min Profit | Minimum post-cut profit | off |
| Min Margin | Minimum % price gap between consecutive listings | 10% |
| AH Cut | Auction house cut applied to resale price | 5% |

Empty / 0 disables a filter, except `Min Listed Qty` (falls back to 1) and `Min Margin` / `AH Cut` (fall back to defaults).

Defaults live in `Core/Constants.lua`:

```lua
PriceJumpRatio = 1.10,
DefaultAHCutPercent = 5,
```

## Dependencies

- [Auctionator](https://www.curseforge.com/wow/addons/auctionator) (required, declared in the TOC).

## Local development on macOS

Use real symlinks — not Finder aliases — so the WoW client resolves the addon folder as a real directory:

```bash
mkdir -p "/Applications/World of Warcraft/_retail_/Interface/AddOns"
mkdir -p "/Applications/World of Warcraft/_classic_era_/Interface/AddOns"

rm -rf "/Applications/World of Warcraft/_retail_/Interface/AddOns/AuctionatorFlipFinder"
rm -rf "/Applications/World of Warcraft/_classic_era_/Interface/AddOns/AuctionatorFlipFinder"

ln -s "$HOME/Documents/AuctionatorFlipFinder" "/Applications/World of Warcraft/_retail_/Interface/AddOns/AuctionatorFlipFinder"
ln -s "$HOME/Documents/AuctionatorFlipFinder" "/Applications/World of Warcraft/_classic_era_/Interface/AddOns/AuctionatorFlipFinder"
```

Replace the source path with wherever your local repo lives if it isn't under `Documents/`.
