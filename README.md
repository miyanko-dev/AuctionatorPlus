# Auctionator Plus

A companion add-on for [Auctionator](https://www.curseforge.com/wow/addons/auctionator) that adds price-history and gear-pricing tools to the Auction House.

## Features

- **Price-history tooltips** — item tooltips carry a **Market Value** section (one row per source: *Auctionator*, the average minimum buyout from your scans, and *TSM*, tagged with the app data's age) and a **Relative Value** section comparing the last known price against each anchor, coloured for the active view at the Auction House. Stays out of the way inside the buy detail and sell-item views.
- **Check Similar Items** — enable the checkbox in the Selling tab. When you place a gear item to sell, a background Auction House search runs (no tab switching) for the same **slot + armor type** within **±2 of the required level**, and the matches are listed in the Selling tab's current-prices panel alongside Auctionator's usual name-based results.
- **Same Stats** — a second checkbox next to *Check Similar Items*. When also enabled, the comparables are narrowed to items carrying the **same stats** as the item being sold (stat names, any value; DPS presence for weapons). Example: listing cloth boots with Intellect + Stamina at level 50 shows other level 48–52 cloth boots with exactly Intellect and Stamina — not ones that also have Spirit. With it off, every same-slot/armor-type/level item is shown.
- **Rel. Value columns** — the shopping results and current-prices listings gain a *Rel. Value* column showing each item's price against its 21-day average minimum buyout (green when favourable for the view), so underpriced deals stand out at a glance.
- **Green bag glow** — in the Selling tab's bag panel, items whose last known price sits above both their 21-day Auctionator average and their TSM market value get a green glow faded over their icon (the game's own `bags-glow-green`), so profitable sells stand out at a glance — including green-quality items, whose border is already green. Items missing either price signal stay unmarked.
- **Sale Scan** — a button right of the money display in the Selling tab, on the same line as the bottom-row buttons. One click runs a live exact-name price search for every distinct item in the bag panel, like scanning a shopping list (sequential, throttle-aware, with the current-prices panel showing the same loading spinner and "Search for item X/Y" progress line a list scan does, and the button flipping to *Cancel Scan* while it runs), feeding Auctionator's price database so *Rel. Value* and the green glow reflect current prices instead of your last scan. The scan steps aside as soon as you place an item for sale or run your own search.
- **TSM data rows** — with the TSM desktop application running and the TradeSkillMaster_AppHelper addon present, AuctionatorPlus captures the app's realm market data on login (TSM itself receives it unchanged) and fills the *TSM* rows of both tooltip sections. Without app data the rows stay hidden and a short setup hint shows at the tooltip bottom instead. Fresh app data is picked up on login or `/reload`.

## Usage

1. In the Selling tab, tick **Check Similar Items**, then drop a gear item — comparable auctions appear in its current-prices list automatically.
2. Hover an item to see its price history.
3. Sort shopping results by the **Rel. Value** column to surface underpriced items.

The tooltip block and trend columns share the data Auctionator already collected. The similar-items search runs in the background on the Selling tab (no tab switching) and merges into the current-prices listing.

## Requirements

- WoW Classic Era / Anniversary 1.15.x
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator)
