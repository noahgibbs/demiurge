require "demiurge/dsl"

require "tmx"

# TMX support here includes basic/normal TMX support for products of
# the Tiled map editor (see "http://mapeditor.org" and
# "http://docs.mapeditor.org/en/latest/reference/tmx-map-format/") and
# more complex tiled map support for formats based on the ManaSource
# game engine, including variants like Source of Tales, Land of Fire,
# The Mana World and others. For more information on the ManaSource
# mapping format, see "http://doc.manasource.org/mapping.html".

# In general, Tiled and "raw" TMX try to be all things to all
# games. If you can use a tile editor for it, Tiled would like to do
# that for you.  ManaSource is a more specialized engine and
# introduces new concepts like named "Fringe" layers to make it clear
# how a humanoid sprite walks through the map, named "Collision"
# layers for walkability and swimmability, known-format "objects" for
# things like doors, warps, NPCs, NPC waypoints and monster spawns.
# Not all of that will be duplicated in Demiurge, but support for such
# things belongs in the (opt-in) ManaSource TMX parsing code.

# In the long run, it's very likely that there will be other TMX
# "dialects" like ManaSource's. Indeed, Demiurge might eventually
# specify its own TMX dialect to support non-ManaSource features like
# procedural map generation. My intention is to add them in the same
# way - they may be requested in the Demiurge World files in the DSL,
# and they will be an additional parsing pass on the result of "basic"
# TMX parsing.

module Demiurge
  class ZoneBuilder
    def tmx_location(name, &block)
      builder = TmxLocationBuilder.new(name)
      builder.instance_eval(&block)
      @locations << builder.built_location
      @location_actions << builder.built_actions
      nil
    end
  end

  class TmxLocationBuilder < LocationBuilder
    def tile_layout(tmx_spec)
      # Make sure this loads correctly
      Demiurge.sprites_from_tmx(tmx_spec)

      @state["tile_layout"] = tmx_spec
    end

    def manasource_tile_layout(tmx_spec)
      # Make sure this loads correctly
      Demiurge.sprites_from_manasource_tmx(tmx_spec)

      @state["manasource_tile_layout"] = tmx_spec
    end

    def built_location
      raise("A TMX location (name: #{@name.inspect}) must have a tile layout!") unless @state["tile_layout"] || @state["manasource_tile_layout"]
      [ "DslTmxLocation", @name, @state ]
    end
  end

  class DslTmxLocation < DslLocation
    def initialize(name,engine)
      super
    end

    def tiles
      raise("A TMX location (name: #{@name.inspect}) must have a tile layout!") unless state["tile_layout"] || state["manasource_tile_layout"]
      DslTmxLocation.tile_cache_entry(state["manasource_tile_layout"], state["tile_layout"])
    end

    # Technically a StateItem of any kind has to be okay with its
    # state changing totally out from under it at any time.  One way
    # around that for TMX is a tile cache to parse new entries and
    # re-return old ones.  This means if a file is changed at runtime,
    # its cache entry won't be reloaded.
    def self.tile_cache_entry(state_manasource_tile_layout, state_tile_layout)
      smtl = state_manasource_tile_layout
      stl = state_tile_layout
      @tile_cache ||= {
        "manasource_tile_layout" => {},
        "tile_layout" => {},
      }
      if smtl
        @tile_cache["manasource_tile_layout"][smtl] ||= Demiurge.sprites_from_manasource_tmx(smtl)
      elsif stl
        @tile_cache["tile_layout"][stl] ||= Demiurge.sprites_from_tmx(stl)
      else
        raise "A TMX location must have some kind of tile layout!"
      end
    end
  end
end

Demiurge::TopLevelBuilder.register_type "DslTmxLocation", Demiurge::DslTmxLocation

module Demiurge
  # This is to support TMX files for ManaSource, ManaWorld, Land of
  # Fire, Source of Tales and other Mana Project games. It can't be
  # perfect since there's some variation between them, but it can
  # follow most major conventions.

  # TODO: ambient layers from properties, a la Evol (see 000-0.tmx)

  def self.sprites_from_manasource_tmx(filename)
    objs = sprites_from_tmx filename
    #sheet = objs[:spritesheet]
    stack = objs[:spritestack]

    stack_layers = stack[:layers]

    # Remove the collision layer, add as separate collision top-level entry
    collision_index = stack_layers.index { |l| l[:name].downcase == "collision" }
    collision_layer = stack_layers.delete_at collision_index

    # Some games make this true/false, others have separate visibility
    # or swimmability in it. In general, we'll just expose the data.
    objs[:collision] = collision_layer[:data]

    # Remove the heights layer, add as separate heights top-level entry
    heights_index = stack_layers.index { |l| ["height", "heights"].include?(l[:name].downcase)  }
    heights_layer = stack_layers.delete_at heights_index
    objs[:heights] = heights_layer

    fringe_index = stack_layers.index { |l| l[:name].downcase == "fringe" }
    stack_layers.each_with_index do |layer, index|
      # Assign a Z value based on layer depth, with fringe = 0 as a special case
      layer["z"] = (index - fringe_index) * 10.0
    end

    objs
  end

  def self.frames_from_tileset(tileset)
    frames = []
    framecount = 0

    ycoords = [tileset.margin]
    ycoords.push(ycoords[-1] + tileset.tileheight + tileset.spacing) until (ycoords[-1] + tileset.spacing) >= tileset.imageheight - tileset.margin - tileset.tileheight

    xcoords = [tileset.margin]
    xcoords.push(xcoords[-1] + tileset.tilewidth + tileset.spacing) until (xcoords[-1] + tileset.spacing) >= tileset.imagewidth - tileset.margin - tileset.tilewidth

    ycoords.each do |y|
      xcoords.each do |x|
        framecount += 1
        frames.push({
                      gid: tileset.firstgid + framecount,
                      image: "/tiles/" + tileset.image.split("/")[-1],
                      x: x,
                      y: y,
                      width: tileset.tilewidth,
                      height: tileset.tileheight })
      end
    end

    frames
  end

  def self.sprites_from_tmx(filename)
    spritesheet = {}
    spritestack = {}

    # This recursively loads things like tileset .tsx files
    tiles = Tmx.load filename

    spritestack[:name] = tiles.name || File.basename(filename).split(".")[0]
    spritestack[:width] = tiles.width
    spritestack[:height] = tiles.height
    spritestack[:properties] = tiles.properties

    spritesheet[:tilewidth] = tiles.tilewidth
    spritesheet[:tileheight] = tiles.tileheight

    spritesheet[:images] = tiles.tilesets.map do |tileset|
      {
        firstgid: tileset.firstgid,
        tileset_name: tileset.name,
        image: "/tiles/" + tileset.image.split("/")[-1],
        image_width: tileset.imagewidth,
        image_height: tileset.imageheight,
        tile_width: tileset.tilewidth,
        tile_height: tileset.tileheight,
        oversize: tileset.tilewidth != tiles.tilewidth || tileset.tileheight != tiles.tileheight,
        spacing: tileset.spacing,
        margin: tileset.margin,
        imagetrans: tileset.imagetrans, # Currently unused, color to treat as transparent
        properties: tileset.properties,
        frame_definitions: frames_from_tileset(tileset),
      }
    end
    spritesheet[:cyclic_animations] = animations_from_tilesets tiles.tilesets

    spritesheet[:properties] = spritesheet[:images].map { |i| i[:properties] }.inject({}, &:merge)
    spritesheet[:name] = spritesheet[:images].map { |i| i[:tileset_name] }.join("/")
    spritestack[:spritesheet] = spritesheet[:name]

    spritestack[:layers] = tiles.layers.map do |layer|
      data = layer.data.each_slice(layer.width).to_a
      {
        name: layer.name,
        data: data,
        visible: layer.visible,
        opacity: layer.opacity,
        offsetx: layer.offsetx,  # Currently unused
        offsety: layer.offsety,  # Currently unused
        properties: layer.properties,
      }
    end

    objects = tiles.object_groups.flat_map { |og| og.objects.to_a }.map(&:to_h)

    { spritesheet: spritesheet, spritestack: spritestack, objects: objects }
  end

  def self.animations_from_tilesets tilesets
    tilesets.flat_map do |tileset|
      (tileset.tiles || []).map do |tile|
        p = tile["properties"]
        if p && p["animation-frame0"]
          section = 0
          anim = []

          while p["animation-frame#{section}"]
            section_hash = {
              frame: p["animation-frame#{section}"].to_i + tileset[:firstgid],
              duration: p["animation-delay#{section}"].to_i
            }
            anim.push section_hash
            section += 1
          end
          { "tile_anim_#{tile["id"].to_i + tileset[:firstgid]}".to_sym => anim }
        else
          nil
        end
      end.compact
    end.inject({}, &:merge)
  end

end
