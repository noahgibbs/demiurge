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
than one specific abstraction that Demiurge defines. Entities
generally can act and be acted on, can pick things up and be picked
up, can take place in a location or be that location. In general, a
single individual entity will only do a few of those things, though.

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
data. Each State Item gets a chunk of state and manages its own
rules. Each State Item's item name must be unique. There may be lots
of a particular *kind* of state item, but each one gets its own unique
name and its own chunk of state.

A "State Item" applies rules to state. As a programmatic object, it
can apply its rules (which are fixed) to its state (which can change
at any time).

This abstraction makes it easy to consider hypotheticals -- to ask,
"if the state were different in this way, how would that change the
world?"

== Item Naming and Instances

A Demiurge entity (including Zones, Locations, Agents and many others)
must have a single, fully unique name within a given Engine. In World
Files, normally a human has to declare the name and that name needs to
be unique.

Names have a few restrictions. You can use alphanumeric characters
(letters and numbers, including Unicode letters and numbers) along
with spaces, dashes and underscores in the names. But other
punctuation including quotes, hash signs, dollar signs and so on
aren't permitted. These names are used internally as unique
identifiers and you don't need to worry about showing them to humans,
so don't worry about not being able to put punctuation you care about
in the names. The names are case-sensitive -- that is, "Bobo" and
"boBo" are completely different items because an upper-case and
lower-case letter count as different from each other.

Certain items, such as Zones in World Files may be reopened by
declaring another item (e.g. another Zone) with the same name. But if
so, they aren't two different Zones with the same name. Instead, the
files declare a single Zone across multiple files. That's perfectly
legal, just as you may declare a room in one World File while
declaring creatures and items inside it in another World File. But
it's all a single room, even if it's declared in multiple places for
human convenience. If you're used to programming with Ruby classes,
this idea of "reopening" the same zone in a new file will probably
seem very familiar.

Sometimes you want to declare an object and then have a lot of
them. Something like a wooden spoon, a low-level slime monster or a
player body object may get just one declaration in the World Files for
a lot of individual objects in the world. Differences in state or
appearance can add variation where you need it without requiring
giant, bloated World Files with fifteen identical slime monsters that
just have a "7" or a "12" after their name.

There are a few kinds of special punctuation in names and name-like
things that Demiurge may use for itself. For instance, a Position (see
later in this file) is a location's item name followed by a pound sign
and then some additional information, such as
"my\_room#25,71". Certain special objects and other things in Demiurge
can use other punctuation (e.g. colon or dollar-sign), but these
shouldn't occur in human-named objects in World Files.

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
it. It may be literally kept immutable in the program, depending on
required efficiency.

For each tick, code runs to generate Intentions on the part of any
entities that can act. Anything that will change state or create a
Notification requires an Intention.

Then, in some order of precedence, these Intentions are resolved one
at a time.

First an Intention is "validated" - can it happen at all? If not, it
is discarded as impossible, undesirable or otherwise "not going to
happen" with no effects of any kind.

At this point, the state becomes changeable again. This may involve
unfreezing or copying.

Then an Intention is offered - other entities may attempt to block,
modify or otherwise interfere with what occurs. This may result in the
Intention being blocked as in the validation stage (another entity
effectively makes its result impossible, resulting in nothing
happening) or its effects may be modified and/or other effects may
immediately occur as a result.

As that process resolves, the Intention may modify state. It may also
send Notifications. In general, a Notification reflects a completed
operation and the receiver can only react, not change or block the
action. While a Notification allows the receiver to modify state, that
receiver should only modify its own state or send additional
Notifications - it should not take "instant reactions", which should
be resolved in the offer/modify/veto stage.

After all these Notifications have resolved, including any
Notifications raised in response to other Notifications, the tick
begins again with the new state, which may be frozen during the early
Intention phases.

== Zones, Location and Position

Location in Demiurge starts with the Zone. A Zone is a top-level
entity that manages state and flow of execution roughly independently
of other zones.

Different Zones may have very different "physics" between them - a
Zone might be entirely text descriptions, while a different Zone is
managed entirely in 2D tile graphics, for instance and a third Zone
could be an HTML UI. It's possible to do that within a single Zone in
some cases, if the Zone's "physics" permit it, but such changes are
expected between Zones.

A Location within a Zone may have some difference, but needs to
cooperate effectively with the Zone and with other Locations
inside. In a 2D tile-based Zone, it may be important that Zone
pathfinding works across multiple Locations, for instance. In a
text-based Zone of mostly-independent locations, there may be a
notification system that allows events in adjacent rooms to be visible
in certain other rooms as text notifications.

In general, a Zone defines the top-level "physics" and the nature of
space and location within itself, and Locations coordinate to make
that happen. Technically Locations are optional - it's possible for a
Zone to skip Locations entirely. But ordinarily there is some form of
subdivision.

Locations are also allowed to contain other Locations, and may do so
or not depending on the nature of their Zone.

When one asks for an entity's "location", one may mean "what entity
inside a Zone is it contained in?" However, there is not always a
well-defined answer to that question. For instance, an "infinite
space" Zone with no sub-locations that handles all object interactions
directly may not have "Location" sub-objects within itself at
all. What "location" is somebody at within the Zone? The Demiurge
entity in question is just the Zone, since there are no smaller
Location entities within it.

And within a Location, an entity may occupy different positions. In a
box of 3D space or a 2D tile map or a MUD-style room with objects
inside, a given entity may be at "x: 27.4, y:-1547.2, z: 297.0" or "x:
27, y: 5" or "next to the gray lamp."

The Demiurge class "Demiurge::Location" is basically advisory -
locations within a Zone aren't required to belong to that class, may
be part of a tree of different location objects or may not exist at
all.

As a result, a "location" in Demiurge is about author intention, not
really about what Demiurge does with the object in question. The Zone
defines what being a location means, and it may vary widely from Zone
to Zone.

But then, how does one specify? With a Position.

A Position is given relative to a Zone or an object inside the Zone,
such as a Location (if one exists.) It is of the form
"item\_name#coordinates" where "item\_name" is a canonical
Demiurge item name, instanced or non-instanced. The coordinates may be
in a form appropriate to their zone such as "7,25" or
"29.45/81.6/Kappa" or "left\_of/gray\_greasy\_lamp". The coordinates
should not contain a pound-sign, a dollar sign or other characters
that aren't legal in a Demiurge item name.

== The Admin Zone and Positionless Actions

Sometimes, a thing happens that doesn't belong in any specific game
zone. A player might fail to create a new account - what zone would
that belong in? An admin might reload the whole world, which isn't
specific to any one zone. An error might occur that can't be traced to
any specific zone.

When that happens, a special zone name, "admin", is used. There cannot
be an "admin" zone in a world file. Instead, "admin" is the name of an
automatic InertStateItem which holds system information like how many
total ticks have passed in the world, and the current notification_id
and intention_id for queueing.

Positionless occurrences like the examples above (e.g. account
creation failures) will appear to occur in this nonexistent "admin"
zone.
