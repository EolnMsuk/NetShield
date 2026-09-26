#pragma once
// Traffic direction, not connection initiator. Replies need inbound permission.
enum { NSInbound = 1, NSOutbound = 2, NSBoth = 3, NSUnknown = -1 };
static inline int NSValidRule(int mask) { return mask >= 0 && mask <= NSBoth; }
static inline int NSAllows(int enabled, int mask, int direction) {
    if (direction != NSInbound && direction != NSOutbound) return 0;
    if (!enabled) return 1;
    return NSValidRule(mask) && (mask & direction) == direction;
}
static inline int NSCachedAllows(int mask, int direction, double now, double lastReply) {
    return lastReply > 0 && now >= lastReply && now - lastReply < 3.0 &&
           NSAllows(1, mask, direction);
}

// Public rule choices: block both, block incoming (allow outgoing), allow both.
static inline int NSSelectableRule(int mask) { return mask == 0 || mask == NSOutbound || mask == NSBoth; }
// Retiring inbound-only must never silently grant outgoing access.
static inline int NSNormalizeStoredRule(int mask) { return mask == NSInbound ? 0 : mask; }
