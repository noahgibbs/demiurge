# Reloading, Debugging and Demiurge Engines

Demiurge tries to make it easy to reload World Files in
development. What's so complicated about that?

Where possible, Demiurge tries to just keep the same zones, locations,
agents and so on with the same action names. If you change the code
for something that already exists, great! Demiurge can easily put that
together and give you the new code.

Fabulous. All done, right?

Nope. What if you rename a zone? You probably don't *want* Demiurge to
try to guess that based on the line in the file, or the new name. If
it gets it right 60% of the time (which is optimistic)... Well, what
about the other 40%? Also, you won't be in the habit of noticing and
fixing it, which will occasionally be *really* bad.

So: expect this to be okay for development. Do *not* expect it to work
perfectly, nor for you to be able to test a bunch of development
changes with incremental reloads and then have it work perfectly in
production later.

State is hard. Reloading is hard. Demiurge has some ways to help a
little. But this is all still hard.

## Resetting

## Simple Best Practices

When Demiurge loads your World Files, it has to execute them as Ruby
code. That means if you do something as a side effect (print to
console, write a file) it gets done every time. So try not to do that.

## What Makes This Easier?

Players love big persistent games like Minecraft where everything they
do persists forever and they can make huge changes to the game. And
yet there are very few games like that. Why?

Partly because it's really, really hard to *test* changes to a world
like that. Wouldn't it be cool if you could add new lava-or-water-type
blocks to Minecraft and change how they worked? Maybe you could make
some kind of slime-or-pudding block that poured and flowed like that?
And then make pudding sculptures, like those wonderful towers or
fortresses you make with water or lava pouring over them in Minecraft
Creative Mode? Now, think about how you'd *test* those changes in a
big persistent Minecraft-type world where everybody was building stuff
all the time.

(For the same reason, a Minecraft MMO would be a *gigantic* pain to
create. Just sayin'.)

If you were making changes to how the pudding blocks worked, you'd
have players *howling* every time the flow changed and their
fortresses looked different. You can't just put that out there and
then mess with it -- the "mess with it" part is really hard in a big
persistent world. Players get really attached to every small change.

So what do you do? Well, one thing is to wipe the slate clean,
regularly. Minecraft doesn't guarantee that you know exactly where
every skeleton or creeper is, and mostly you don't expect to. Most
games are even more like that -- World of Warcraft knows where
monsters *spawn* and it knows their *routes*, but you don't expect to
come back an hour later and see anything you did persist. Dropped
items disappear, killed monsters come back.

By having a lot of non-persisted state (information the game is
allowed to wipe clean), you leave room for making changes. If an admin
messes around with exactly how monsters spawn (how many? what timing?
do they roam around a little? where?) that doesn't feel like a big
deal -- you're used to that information getting reset constantly, and
little changes to it feel like window dressing. You forgot exactly
which monsters you killed thirty seconds after you killed them because
you don't *expect* that to be useful to remember. The spawn points
might be important - especially if you're used to sneaking past them
or quietly taking a route that keeps you out of the way of the big
nasties. But even changing those spawn points feels "fair" - it's
different from losing track of, say, how much gold your character
currently has, or exactly which blocks you put where in Minecraft to
make a shelter.

In general, you should make it clear when there's information you
won't be persisting. If you need to wipe out dropped weapons on the
floor (you probably do) then start that decay process *early* - you
want folks to know it's possible so that it's not a horrible surprise
when it happens.

And you want to persist as little information as you can get away
with. Any part of the game world that you (the admin) are allowed to
play with or reset is information you don't need to keep intact as
precious player data.


