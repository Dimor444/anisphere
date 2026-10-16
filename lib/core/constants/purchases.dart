// What money can buy in the app: nothing yet. Both stores sold things that
// could not be bought.
//
// Coming back needs real purchases, and for digital goods in the iOS app that
// means Apple's in-app purchase. App Store Review Guideline 3.1.1, as of
// 2026-10-17: "If you want to unlock features or functionality within your
// app, (by way of example: subscriptions, in-game currencies, game levels,
// access to premium content, or unlocking a full version), you must use
// in-app purchase." Outside the United States storefront, apps also "may not
// include buttons, external links, or other calls to action that direct
// customers to purchasing mechanisms other than in-app purchase" (3.1.1(a),
// 3.1.3) — and the Recharge tab listed Apple Pay, Google Pay, card and PayPal
// beside its gem packs. The grant itself must then be written server-side,
// after the server verifies the store's receipt: AniGold, AniGem and isPlus
// are server-owned fields the client cannot set.

/// Whether AniGems exist at all: the wallet's Recharge tab and every gem
/// balance (wallet header, the feed's currency pill, the drawer).
///
/// Recharge sold gem packs at $0.99–$14.99 and every tap answered "Demo — no
/// real purchase". Nothing else grants a gem — the rules pin it to 0 when a
/// profile is created and no function writes it — and nothing spends one, so
/// every balance read 0. Coming back needs in-app purchase products for the
/// packs, a server that verifies the receipt and credits the gems, and
/// something gems buy.
const bool kAniGemsEnabled = false;

/// Whether AniPlus is offered for sale: the wallet's AniPlus tab, the
/// paywall's Subscribe, the drawer's "Upgrade to AniPlus" and every upsell
/// link to them.
///
/// The tab priced a "Coming Soon" plan at $4.44 a month, listed sixteen
/// features — most of which do not exist — and checked discount codes on the
/// device against sample data. isPlus is server-owned and nothing grants it,
/// so every upsell led to a plan that could not be bought. Coming back needs
/// an in-app purchase subscription, a server that verifies it and writes
/// users/{uid}.isPlus, and a feature list of what Plus actually unlocks. The
/// Plus checks themselves stay: a Plus account still gets what Plus grants.
const bool kAniPlusForSale = false;
