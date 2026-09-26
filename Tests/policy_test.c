#include <assert.h>
#include <stdio.h>
#include "../Sources/Policy.h"
int main(void) {
    assert(!NSAllows(1, NSUnknown, NSInbound));
    assert(!NSAllows(1, NSUnknown, NSOutbound));
    assert(!NSAllows(1, 0, NSInbound));
    assert(!NSAllows(1, 0, NSOutbound));
    assert(NSAllows(1, NSInbound, NSInbound));
    assert(!NSAllows(1, NSInbound, NSOutbound));
    assert(NSAllows(1, NSOutbound, NSOutbound));
    assert(!NSAllows(1, NSOutbound, NSInbound));
    assert(NSAllows(1, NSBoth, NSInbound));
    assert(NSAllows(1, NSBoth, NSOutbound));
    assert(NSAllows(0, NSUnknown, NSInbound));
    assert(NSAllows(0, 0, NSOutbound));
    assert(!NSAllows(1, 4, NSInbound));
    assert(!NSAllows(1, 255, NSOutbound));
    assert(!NSAllows(0, NSBoth, 0));
    assert(!NSAllows(1, NSBoth, NSBoth));
    assert(!NSCachedAllows(NSBoth, NSOutbound, 1, 0)); // No broker reply yet
    assert(NSCachedAllows(NSBoth, NSOutbound, 101, 100));
    assert(NSCachedAllows(NSBoth, NSInbound, 102.999, 100));
    assert(!NSCachedAllows(NSBoth, NSOutbound, 103, 100)); // Expiry boundary
    assert(!NSCachedAllows(NSBoth, NSOutbound, 500, 100)); // Broker disappeared
    assert(!NSCachedAllows(NSUnknown, NSOutbound, 101, 100)); // Invalidation
    assert(!NSCachedAllows(NSBoth, NSOutbound, 99, 100)); // Invalid clock order
    assert(NSCachedAllows(NSBoth, NSOutbound, 501, 500)); // Recovery
    assert(NSSelectableRule(0));
    assert(NSSelectableRule(NSOutbound));
    assert(NSSelectableRule(NSBoth));
    assert(!NSSelectableRule(NSInbound));
    assert(!NSSelectableRule(NSUnknown));
    for (int old = 0; old <= NSBoth; ++old) {
        int migrated = NSNormalizeStoredRule(old);
        assert(NSSelectableRule(migrated));
        assert((migrated & ~old) == 0); // Migration cannot grant a new direction.
    }
    puts("Policy tests passed");
    return 0;
}
