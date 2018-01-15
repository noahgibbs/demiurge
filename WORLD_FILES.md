# Demiurge World Files

Demiurge includes a very convenient Ruby DSL (Domain-Specific
Language) for declaring your zones, locations, agents and so on. These
are referred to as World Files, and are by far the easiest and most
common way to create a simulation using Demiurge.

Unfortunately, the Builder classes in the API documentation aren't a
great way to document the World File syntax and how to use it. There
are some good examples, but many of them are either too complicated,
or intentionally weird. For instance, the test/ directory is full of
World File examples that are designed to test weird corner cases or
generate errors or both.

This is a quick guide to using World Files. It's not full and
comprehensive. But it may provide a kick-start, after which the
Builder classes won't seem quite so bizarre and inscrutable.

Normally World Files are stored in a directory in your game. I like
calling it "world". If you used multiple Demiurge engines for some
reason, you'd probably want to store their two sets of World Files in
two different directories.  But for a single Engine, you'd normally
want a single directory of World Files.

## Getting Started

Your game will need to load its World Files somehow. Here's a good
simple example of how to do that:

    Dir["**/world/extensions/**/*.rb"].each do |ruby_ext|
      require_relative ruby_ext
    end
    @engine = Demiurge.engine_from_dsl_files *Dir["world/*.rb"]

This example doesn't try to do any kind of sorting to load the files
in a particular order. In other words, you'll need to do something
fancier if your game gets big.

It also assumes that all your World Files are in the top-level
directory, which won't stay true for long either. So: you can start
with this example, but you'll need to change it later.

## Your First Zone

Here's an example file containing a very simple zone for use with
Demiurge-CreateJS:

    zone "trackless island" do
      tmx_location "start location" do
        manasource_tile_layout "tmx/trackless_island_main.tmx"
        description "A Mysterious Island"
      end
    end

If you're using Demiurge-CreateJS (aka DCJS) then you'll probably want
to use 2D tile-based locations, also called TmxLocations. Those are
the ones you can generate using the Tiled map editor. See
Demiurge-CreateJS for more details.

If you're using Demiurge on your own projects without DCJS, you can do
that too. Here's an example administrative zone containing a player
definition:

    # Player information can be stored here. In general, if you want
    # information to stick around it needs a StateItem.  An "inert"
    # StateItem just means it doesn't change on its own or take any
    # actions.
    inert "players"
    
    zone "adminzone" do
      agent "player template" do
        # No position or location, so it's instantiable.
    
        # Special action that gets performed on character creation
        define_action("create", "engine_code" => true) do
          if ["bob", "angelbob", "noah"].include?(item.name)
            item.state["admin"] = true
          end
        end
    
        define_action("statedump", "tags" => ["admin", "player_action"]) do
          dump_state
        end
      end
    end

You can create interesting object interactions with actions. You can
see a few actions above, but they're just the tip of the iceberg.
Here's a fun example where an agent can kick some stones down a cliff
and they'll start a mini-avalanche. The bigger the initial kick, the
bigger (by far) the total number of stones falling down:

    zone "echoing cliffs" do
      location "cliffside" do

        agent "stone kicker" do
          define_action "kick stones" do |how_many|
            notification type: "echoing noise", "stone size": how_many, location: item.location_name
            how_many -= 1
            if how_many > 0
              action "kick stones", how_many
              action "kick stones", how_many
            end
          end
        end
      end
    end

Each action block (the do/end part) is just Ruby code, so you can do
whatever Ruby can do there. The hard part is just figuring out what
information you can work with, and what you're allowed to do with
it. The methods above called "notification", "action" and "dump_state"
above are all standard and can be found in the BlockRunner classes -
that's AgentBlockRunner, ActionItemBlockRunner and EngineBlockRunner,
depending on how you run it. Agents get the AgentBlockRunner,
ActionItems get the ActionItemBlockRunner, and you only get the
EngineBlockRunner if you specifically pass the ":engine_code" option
to your action.

## Security

There's a SECURITY guide in its own file. But the short version is:
keep in mind that World Files are *not* secure. You should read
through any World File that somebody else gives you completely before
you add it to your game. A bad World File can steal your in-game
passwords and code. It can even attack other programs running on the
same server as your game (which might be your home computer, where you
do your banking.) It can send somebody else your data, and it can
download other code from the Internet if it's connected to the
Internet.

Do *not* accept unknown World Files from other people. It's like
running a downloaded .EXE on a Windows machine - it can do whatever
your computer can, and you really shouldn't let it.
