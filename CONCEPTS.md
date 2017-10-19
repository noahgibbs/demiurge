= Demiurge Simulated Worlds

Demiurge is a great way to prototype and develop an interesting
simulated world. It's intended to be flexible, powerful and easy to
tie into other systems.

Let's talk about the components of a Demiurge world and what they do.

== Engines, State, Ticks

A single Demiurge simulation is called an Engine. It can be loaded
from World Files and state.

World Files determine the behavior of the world - what kinds of
entities does the world contain? How do they act? What are the rules
of physics that define that world?

State determines the current situation of that world. If your world
physics allows any number of rabbits in a particular field, how many
are there right now and where are they?

A single step of simulation is called a "tick", like the ticking of a
clock.

The world "entity" for a thing in the world is fairly vague. It may
refer to an "item", a "creature", an "area" (another vague word) or
something else. An entity is "a thing or things in the world" rather
than one specific abstraction that Demiurge defines.

== Intentions, Actions and Events

A world may contain unchanging things, usually represented as
rules. It may contain changeable and movable items. And it may contain
items or creatures that act on their own. Demiurge can distinguish
between these categories, but it usually does so by distinguishing
between "rules" and "state" rather than between "intelligent" and
"unintelligent." Intelligence is mostly a matter of how complex the
rules are, and what objects they tend to affect.

A Demiurge Engine normally moves forward in discrete steps. The
current state is examined to create a list of Intentions, which do not
(yet) change state. The Intentions are then resolved into
notifications and state changes. One full state/intention/event cycle
is a tick.

Demiurge doesn't require that ticks occur at particular times
according to a real-world clock. You might choose to create entities
and rules that care about a real-world clock, but Demiurge doesn't
care. Ticks can be evenly spaced or not, as long as your entities'
rules reflect that.

== State Items, and the Difference Between Rules and State

Rules exist entirely within World Files and the Demiurge framework
itself. The effects of rules can change according to current state,
but the rules themselves are in the World Files and do not depend on
state.

State in Demiurge must be serializable as JSON. That gives a
combination of numbers, strings, true/false/undefined special values,
lists and objects (dictionaries/hashes) as the set of all state
data. There is a single full state "tree" in Demiurge, where each
State Item gets a chunk of state attached to its item name. Each item
name must be unique. There may be lots of a particular *kind* of state
item, but each one gets its own unique name and its own chunk of state.

A "State Item" applies rules to state. As a programmatic object, it
can apply its rules (which are fixed) to its state (which can change
at any time).

This abstraction makes it easy to consider hypotheticals -- to ask,
"if the state were different in this way, how would that change the
world?"

== Events and State Changes

Often an Intention turns into a change of state. For example, an item
is picked up, or a person moves from one location to another. When
that occurs, there may also be one or more notifications. The state
change is what it sounds like - if a person moves from one place to
another, their "location" is part of their state, and it's different
after the tick than it was before.

A Notification doesn't necessarily involve a change of state, though
the two will often happen together. The Notification doesn't cause the
state change, though it may be the result of one. A Notification is
simply a discrete that can be perceived in the world. A continuous,
ongoing event is state, not a Notification, though if it begins, ends
or changes significantly it may *cause* a Notification.

If a person moves from one room to another, their location changes and
so their state changes. There is also likely to be a Notification
associated with it - a detectable, trackable event which can be
watched for by other reactive entities in the world.

A Notification doesn't have to involve a state change, though. For
instance, if a character looks around shiftily or grins momentarily,
that doesn't necessarily change any recorded part of their state. But
another character may watch for the Notification and if they detect
it, they may react to it.

== The Cycle of a Tick

Initially, the state is effectively frozen - nothing should change
it. It may be literally kept immutable in the programming language in
question, depending on required efficiency.

For each tick, code runs to generate Intentions on the part of any
entities that can act. Anything that will change state or create a
Notification requires an Intention.

Then, in some order of precedence, these Intentions are resolved one
at a time.

First an Intention is "validated" - can it happen at all? If not, it
is discarded as impossible, undesirable or otherwise "not going to
happen" with no effects of any kind.



== Zones and Location
