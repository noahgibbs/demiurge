= Hacking Demiurge

When in doubt: read the source, tests and examples of course, just
like any other code.

== State, Immutability and JSON

Demiurge is architected in such a way that StateItems contain logic
about how to manipulate state. StateItems, when state is available,
can calculate new Intentions and apply Actions.

State is stored, separately from StateItems, in the Engine. State can
be serialized and swapped out at any time, so StateItems must be able
to operate without remembering their current in-engine state. For the
same reason, they must be very careful about caching state, which may
change arbitrarily between calls to them.

== Zones and Top-Level State

If every StateItem was guaranteed a call every tick, simulation would
slow to a crawl very rapidly as the world expanded. Instead, certain
top-level StateItems called "zones" are guaranteed to be called every
tick and they decide how to manage the flow of execution to their
contents.
