# Hacking Demiurge

When in doubt: read the source, tests and examples of course, just
like any other code.

## State and JSON

Demiurge is architected in such a way that StateItems contain logic
about how to manipulate state. StateItems contain current state and
can calculate new Intentions and apply Actions.

State can be serialized and swapped out at any time, so StateItems
must be able to be disposable and replaceable. Since it's hard to
serialize a procedure as JSON, generally StateItems define actions in
their World Files or Ruby code, and the StateItem contains the names
of the actions. The actual Ruby procedures are either part of the
StateItem subclass Ruby code or they're stored as a proc in the engine
itself.

Similarly, serialized state data often contains item names rather than
actual items. Names are easily serialized and easily handled with a
minimum of fuss, while structures and code are both messy.

## Zones and Top-Level State

If every StateItem was guaranteed a call every tick, simulation would
slow to a crawl very rapidly as the world expanded. Instead, certain
top-level StateItems called "zones" are guaranteed to be called every
tick and they decide how to manage the flow of execution to their
contents.

In general, a Zone manages whether to call various sub-items or
agents, or whether to only call them sometimes, or whether to quiesce
them completely.
