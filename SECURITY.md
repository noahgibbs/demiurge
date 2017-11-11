= Security and User-Supplied Code

Demiurge is designed for an environment with very high-privilege code
(e.g. Demiurge itself, framework code, setup code) and somewhat
lower-privilege code (e.g. world files, certain player actions,
display code like particles.) It is *not* designed to let you just
"drop in" untrusted code and expect everything will be fine, basically
ever.

## Sandboxing

In general, "sandboxing" code to prevent it from doing things you
don't want is very hard. Ruby does nothing to make this easier - only
a few languages are easy to "sandbox", with JavaScript being by far
the most advanced in that specific respect -- it's designed to run in
the browser environment in a very specifically sandboxed way.

There are a few Ruby sandbox implementations (currently leader seems
to be "https://github.com/jwo/jruby-sandbox"), but in general they're
hard to get right. Proving that a particular Ruby snippet can't access
a particular class (say ObjectSpace, which gives full access to 100%
of everything, or any flavor of "eval," or "binding," or...) is very,
very hard.

So: the current Demiurge codebase makes a much simpler assumption:
there are two overall flavors of code and neither is really safe.

The first flavor is administrative code. Anything that runs with full
privilege (actions marked as full-privilege, anything in a framework
file or other non-World dot-rb file) must be examined very
carefully. These are full-danger code that can do absolutely anything,
and you must trust such code as much as the code you wrote for
yourself. They can do anything you can do, and running them "just for
this one person" without fully examining them is a terrible, terrible
idea.

## World Code

The second flavor is world code. Non-administrative zones, actions for
locations and agents and other similar code is world code. It runs
with more restrictions. It doesn't have methods to directly call most
dangerous operations like reloading your world from a state dump or
reloading a zone. You still have to examine it - a creative Ruby coder
can potentially get at just about anything they want to. But the basic
operations it provides are less dangerous, and a very simple chunk of
world code will normally not be able to do anything *too* awful.

However, the Halting Problem
(https://en.wikipedia.org/wiki/Halting_problem) guarantees that we
can't make many guarantees about what code does, and we certainly
can't be sure it returns in a crisp, predictable manner in
general. So: assume that even world code, even very simple world code,
can cause you significant problems.

## Special Cases

There are very restricted cases where you can be sure that everything
is fine. As an intentionally-silly example, if you let the player
supply a six-digit hexadecimal color value and then apply it to be the
color of something using CSS... That's pretty darn securable. If you
want to make that safe, you totally can.

And as an intermediate-difficulty thing, it's not hard to come up with
a definition language for things like particle effects that only have
a few operations, limited conditionals and no loops, which are
essentially safe. At most a bad world-builder might be able to slow
down people's browsers, which isn't a huge deal.

But in general, if a language is Turing Complete
(https://en.wikipedia.org/wiki/Turing_completeness) then there's a way
to make it misbehave in a way you can't automatically detect. Which
means any language interesting enough to build a world in is also
interesting enough to cause you lots of problems with securing it
automatically.

It's still not a bad idea to build special cases. Those are where
you'll be able to let *players* supply content without carefully
vetting it. If you need world-builders to write zones in Ruby then you
need to have somebody review the code manually - there's not going to
be an enforcement system that's good enough to catch all the
problems. But if you want players to color their own gear or even make
up their own custom particle effects, that's probably not a problem.

It's surprising how much you can do with a special-purpose language or
format for just a few specific things. CSS in your browser is an
example of how far you can take this idea, though these days CSS is
Turing Complete too...

## How Do We Do It Right?

There is an eventual solution that could help this a fair bit, at a
cost of performance and complexity. By running a separate Ruby process
with limited privilege, it could become possible to halt a runaway
chunk of world code and watch its operations more carefully - it's
always easier to monitor a chunk of Ruby code from *outside* that Ruby
process.

That gets around problems with the various sandbox libraries -- how do
you avoid them using 100% CPU and never returning? How do you get
around them allocating unlimited memory? These aren't problems you can
get around with a Ruby-space sandbox library, not really. You need to
run the code evaluation in a separate process so that you can limit
those things without putting your limiting code in the same Ruby
interpreter, where "bad actor" code can get at it.
