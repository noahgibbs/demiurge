= Hacking Demiurge

When in doubt: read the source, tests and examples of course, just
like any other code.

== State and JSON

Demiurge is architected in such a way that StateItems contain logic
about how to manipulate state. StateItems contain current state and
can calculate new Intentions and apply Actions.

State can be serialized and swapped out at any time, so StateItems
must be able to be disposable and replaceable. Since it's hard to
serialize a procedure as JSON, generally StateItems define actions in
their files, and the state contains the names of the actions.

Similarly, state generally contains item names rather than actual
items.

== Zones and Top-Level State

If every StateItem was guaranteed a call every tick, simulation would
slow to a crawl very rapidly as the world expanded. Instead, certain
top-level StateItems called "zones" are guaranteed to be called every
tick and they decide how to manage the flow of execution to their
contents.

In general, a Zone manages whether to call various sub-items or
agents, or whether to only call them sometimes, or whether to quiesce
them completely.
