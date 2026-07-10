# Auctionator Plus

A companion add-on for [Auctionator](https://www.curseforge.com/wow/addons/auctionator) that adds price-history and gear-pricing tools to the Auction House.

## Features

- **Price-history tooltips** — hover any item while the Auction House is open to see *Average Min. Buyout*, *Trend*, *Highest Day*, and *Lowest Day*. Stays out of the way inside the buy detail and sell-item views.
- **Check Similar Items** — enable the checkbox in the Selling tab. When you place a gear item to sell, a background Auction House search runs (no tab switching) for the same **slot + armor type** within **±2 of the required level**, and the matches are listed in the Selling tab's current-prices panel alongside Auctionator's usual name-based results.
- **Same Stats** — a second checkbox next to *Check Similar Items*. When also enabled, the comparables are narrowed to items carrying the **same stats** as the item being sold (stat names, any value; DPS presence for weapons). Example: listing cloth boots with Intellect + Stamina at level 50 shows other level 48–52 cloth boots with exactly Intellect and Stamina — not ones that also have Spirit. With it off, every same-slot/armor-type/level item is shown.
- **Trend columns** — the shopping results and current-prices listings gain a *Trend* column showing each item's price against its 21-day average minimum buyout (green when favourable for the view), so underpriced deals stand out at a glance.
- **TSM data feed (opt-in)** — with the TSM desktop application running and the TradeSkillMaster_AppHelper addon present, AuctionatorPlus captures the app's realm market data on login (TSM itself receives it unchanged). **Use TSM Trend** bases the Trend column and tooltip trend on TSM's market value instead of your own scan history (cells that fall back to scan history are marked `*`) — ideal after a break with little or stale scan data. **Import TSM Scans** merges the app's lowest-buyout snapshot into Auctionator's price database on login, like a full scan taken when the app last synced; existing history is never removed. Item tooltips also show *TSM Market Value* with the data's age. Both toggles sit next to the Full Scan button in the shopping tab (the trend toggle also in the selling tab) and default to off. Fresh app data is picked up on login or `/reload`.

## Usage

1. In the Selling tab, tick **Check Similar Items**, then drop a gear item — comparable auctions appear in its current-prices list automatically.
2. Hover an item to see its price history.
3. Sort shopping results by the **Trend** column to surface underpriced items.

The tooltip block and trend columns share the data Auctionator already collected. The similar-items search runs in the background on the Selling tab (no tab switching) and merges into the current-prices listing.

## Requirements

- WoW Classic Era / Anniversary 1.15.x
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator)
