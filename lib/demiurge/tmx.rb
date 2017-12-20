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
# that for you. ManaSource is a more specialized engine and
# introduces new concepts like named "Fringe" layers to make it clear
# how a humanoid sprite walks through the map, named "Collision"
# layers for walkability and swimmability, known-format "objects" for
# things like doors, warps, NPCs, NPC waypoints and monster spawns.
# Not all of that will be duplicated in Demiurge, but support for such
# things belongs in the ManaSource-specific TMX parsing code.

# In the long run, it's very likely that there will be other TMX
# "dialects" like ManaSource's. Indeed, Demiurge might eventually
# specify its own TMX dialect to support non-ManaSource features like
# procedural map generation. My intention is to add them in the same
# way - they may be requested in the Demiurge World files in the DSL,
# and they will be an additional parsing pass on the result of "basic"
# TMX parsing.

module Demiurge
  module DSL
    # Monkeypatch to allow tmx_location in World File zones.
    class ZoneBuilder
      # This is currently an ugly monkeypatch to allow declaring a
      # "tmx_location" separate from other kinds of declarable
      # StateItems. This remains ugly until the plugin system catches up
      # with the intrusiveness of what TMX needs to plug in (which isn't
      # bad, but the plugin system barely exists.)
      def tmx_location(name, options = {}, &block)
        state = { "zone" => @name }.merge(options)
        builder = TmxLocationBuilder.new(name, @engine, "type" => options["type"] || "TmxLocation", "state" => state)
        builder.instance_eval(&block)
        @built_item.state["contents"] << name
        nil
      end
    end

    # Special builder for tmx_location blocks
    class TmxLocationBuilder < LocationBuilder
      # Constructor
      def initialize(name, engine, options = {})
        options["type"] ||= "TmxLocation"
        super
      end

      # Specify a TMX file as the tile layout, but assume relatively little about the TMX format.
      def tile_layout(tmx_spec)
        # Make sure this loads correctly, but use the cache for efficiency.
        TmxLocation.tile_cache_entry(nil, tmx_spec)

        @state["tile_layout"] = tmx_spec
      end

      # Specify a TMX file as the tile layout, and interpret it according to ManaSource TMX conventions.
      def manasource_tile_layout(tmx_spec)
        # Make sure this loads correctly, but use the cache for efficiency.
        TmxLocation.tile_cache_entry(tmx_spec, nil)

        @state["manasource_tile_layout"] = tmx_spec
      end

      # Validate built_item before returning it
      def built_item
        raise("A TMX location (name: #{@name.inspect}) must have a tile layout!") unless @state["tile_layout"] || @state["manasource_tile_layout"]
        super
      end
    end
  end

  # A TmxZone can extract things like exits and collision data from
  # tile structures parsed from TMX files.
  class TmxZone < TileZone
    # Let's resolve any exits through this zone. NOTE: cross-zone
    # exits may be slightly wonky because the other zone hasn't
    # necessarily performed its own finished_init yet.
    def finished_init
      super
      exits = []
      # Go through the contents looking for locations
      contents = state["contents"].map { |ln| @engine.item_by_name(ln) }
      contents.each do |location|
        # ManaSource locations often store exits as objects in an
        # object layer.  They don't cope with multiple locations that
        # use the same TMX file since they identify the destination by
        # the TMX filename.  In Demiurge, we don't let them cross zone
        # boundaries to avoid unexpected behavior in other folks'
        # zones.
        if location.is_a?(TmxLocation) && location.state["manasource_tile_layout"]
          location.tiles[:objects].select { |obj| obj[:type] == "warp" }.each do |obj|
            dest_location = contents.detect { |loc| obj[:properties] && loc.is_a?(TmxLocation) && loc.tiles[:tmx_name] == obj[:properties]["dest_map"] }
            if dest_location
              dest_position = "#{dest_location.name}##{obj[:properties]["dest_x"]},#{obj[:properties]["dest_y"]}"
              src_x_coord = obj[:x] / location.tiles[:spritesheet][:tilewidth]
              src_y_coord = obj[:y] / location.tiles[:spritesheet][:tileheight]
              src_position = "#{location.name}##{src_x_coord},#{src_y_coord}"
              raise("Exit destination position #{dest_position.inspect} loaded from TMX location #{location.name.inspect} (TMX: #{location.tiles[:filename]}) is not valid!") unless dest_location.valid_position?(dest_position)
              exits.push({ src_loc: location, src_pos: src_position, dest_pos: dest_position })
            else
              @engine.admin_warning "Unresolved TMX exit in #{location.name.inspect}: #{obj[:properties].inspect}!",
                                    "location" => location.name, "properties" => obj[:properties]
            end
          end
        end
      end
      exits.each do |exit|
        exit[:src_loc].add_exit(from: exit[:src_pos], to: exit[:dest_pos])
      end
    end

    # Return the list of valid adjacent positions from this one
    def adjacent_positions(pos, options = {})
      location, pos_spec = pos.split("#", 2)
      loc = @engine.item_by_name(location)
      x, y = pos_spec.split(",").map(&:to_i)

      shape = options[:shape] || "humanoid"
      [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]].select { |xp, yp| loc.can_accomodate_shape?(xp, yp, shape) }
    end
  end

  # A TmxLocation is a special location that is attached to a tile
  # layout, a TMX file. This affects the size and shape of the room,
  # and how agents may travel through it. TmxLocations have X and Y
  # coordinates (grid coordinates) for their positions.
  class TmxLocation < Location
    # Parse a tiled position string and return the X and Y tile coordinates
    def self.position_to_coords(pos)
      loc, x, y = position_to_loc_coords(pos)
      return x, y
    end

    # Parse a tiled position string and return the location name and the X and Y tile coordinates
    def self.position_to_loc_coords(pos)
      loc, coords = pos.split("#",2)
      if coords
        x, y = coords.split(",")
        return loc, x.to_i, y.to_i
      else
        return loc, nil, nil
      end
    end

    # When an item changes position in a TmxLocation, check if the new
    # position leads out an exit. If so, send them where the exit
    # leads instead.
    def item_change_position(item, old_pos, new_pos)
      exit = @state["exits"].detect { |e| e["from"] == new_pos }
      return super unless exit  # No exit? Do what you were going to.

      # Going to hit an exit? Cancel this motion and enqueue an
      # intention to do so? Or just send them through? If the former,
      # it's very hard to unblockably pass through an exit, even if
      # that's what's wanted. If the latter, it's very hard to make
      # going through an exit blockable.

      # Eh, just send them through for now. We'll figure out how to
      # make detecting and blocking exit intentions easy later.

      item_change_location(item, old_pos, exit["to"])
    end

    # This just determines if the position is valid at all.  It does
    # *not* check walkable/swimmable or even if it's big enough for a
    # humanoid to stand in.
    def valid_position?(pos)
      return false unless pos[0...@name.size] == @name
      return false unless pos[@name.size] == "#"
      x, y = pos[(@name.size + 1)..-1].split(",", 2).map(&:to_i)
      valid_coordinate?(x, y)
    end

    # This checks the coordinate's validity, but not relative to any
    # specific person/item/whatever that could occupy the space.
    def valid_coordinate?(x, y)
      return false if x < 0 || y < 0
      return false if x >= tiles[:spritestack][:width] || y >= tiles[:spritestack][:height]
      return true unless tiles[:collision]
      return tiles[:collision][y][x] == 0
    end

    # Determine whether this position can accomodate the given agent's shape and size.
    def can_accomodate_agent?(agent, position)
      loc, x, y = TmxLocation.position_to_loc_coords(position)
      raise "Location #{@name.inspect} asked about different location #{loc.inspect} in can_accomodate_agent!" if loc != @name
      shape = agent.state["shape"] || "humanoid"
      can_accomodate_shape?(x, y, shape)
    end

    # Determine whether this coordinate location can accomodate a
    # rectangular item of the given coordinate dimensions.
    def can_accomodate_dimensions?(left_x, upper_y, width, height)
      return false if left_x < 0 || upper_y < 0
      right_x = left_x + width - 1
      lower_y = upper_y + height - 1
      return false if right_x >= tiles[:spritestack][:width] || lower_y >= tiles[:spritestack][:height]
      return true unless tiles[:collision]
      (left_x..right_x).each do |x|
        (upper_y..lower_y).each do |y|
          return false if tiles[:collision][y][x] != 0
        end
      end
      return true
    end

    # Determine whether this coordinate location can accomodate an
    # item of the given shape.
    #
    # For now, don't distinguish between walkable/swimmable or
    # whatever, just say a collision value of 0 means valid,
    # everything else is invalid.
    #
    # TODO: figure out some configurable way to specify what tile
    # value means invalid for TMX maps with more complex collision
    # logic.
    def can_accomodate_shape?(left_x, upper_y, shape)
      case shape
      when "humanoid"
        return can_accomodate_dimensions?(left_x, upper_y, 2, 1)
      when "tiny"
        return can_accomodate_dimensions?(left_x, upper_y, 1, 1)
      else
        raise "Unknown shape #{shape.inspect} passed to can_accomodate_shape!"
      end
    end

    # For a TmxLocation's legal position, find somewhere not covered
    # as a collision on the collision map.
    def any_legal_position
      loc_tiles = self.tiles
      if tiles[:collision]
        # We have a collision layer? Fabulous. Scan upper-left to lower-right until we get something non-collidable.
        (0...tiles[:spritestack][:width]).each do |x|
          (0...tiles[:spritestack][:height]).each do |y|
            if tiles[:collision][y][x] == 0
              # We found a walkable spot.
              return "#{@name}##{x},#{y}"
            end
          end
        end
      else
        # Is there a start location? If so, return it. Guaranteed good, right?
        start_loc = tiles[:objects].detect { |obj| obj[:name] == "start location" }
        if start_loc
          x = start_loc[:x] / tiles[:spritestack][:tilewidth]
          y = start_loc[:y] / tiles[:spritestack][:tileheight]
          return "#{@name}##{x},#{y}"
        end
        # If no start location and no collision data, is there a first location with coordinates?
        if tiles[:objects].first[:x]
          obj = tiles[:objects].first
          return "#{@name}##{x},#{y}"
        end
        # Screw it, just return the upper left corner.
        return "#{@name}#0,0"
      end
    end

    # Return the tile object for this location
    def tiles
      raise("A TMX location (name: #{@name.inspect}) must have a tile layout!") unless state["tile_layout"] || state["manasource_tile_layout"]
      TmxLocation.tile_cache_entry(state["manasource_tile_layout"], state["tile_layout"])
    end

    # Return a TMX object's structure, for an object of the given name, or nil.
    def tmx_object_by_name(name)
      tiles[:objects].detect { |o| o[:name] == name }
    end

    # Return the tile coordinates of the TMX object with the given name, or nil.
    def tmx_object_coords_by_name(name)
      obj = tiles[:objects].detect { |o| o[:name] == name }
      if obj
        [ obj[:x] / tiles[:spritesheet][:tilewidth], obj[:y] / tiles[:spritesheet][:tileheight] ]
      else
        nil
      end
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

Demiurge::DSL::TopLevelBuilder.register_type "TmxZone", Demiurge::TmxZone
Demiurge::DSL::TopLevelBuilder.register_type "TmxLocation", Demiurge::TmxLocation

module Demiurge
  # This is to support TMX files for ManaSource, ManaWorld, Land of
  # Fire, Source of Tales and other Mana Project games. It can't be
  # perfect since there's some variation between them, but it can
  # follow most major conventions.

  # Load a TMX file and calculate the objects inside including the
  # Spritesheet and Spritestack. Assume this TMX file obeys ManaSource
  # conventions such as fields for exits and names for layers.
  def self.sprites_from_manasource_tmx(filename)
    objs = sprites_from_tmx filename
    stack = objs[:spritestack]

    stack_layers = stack[:layers]

    # Remove the collision layer, add as separate collision top-level entry
    collision_index = stack_layers.index { |l| l[:name].downcase == "collision" }
    collision_layer = stack_layers.delete_at collision_index if collision_index

    # Some games make this true/false, others have separate visibility
    # or swimmability in it. In general, we'll just expose the data.
    objs[:collision] = collision_layer[:data] if collision_layer

    # Remove the heights layer, add as separate heights top-level entry
    heights_index = stack_layers.index { |l| ["height", "heights"].include?(l[:name].downcase)  }
    heights_layer = stack_layers.delete_at heights_index if heights_index
    objs[:heights] = heights_layer

    fringe_index = stack_layers.index { |l| l[:name].downcase == "fringe" }
    stack_layers.each_with_index do |layer, index|
      # Assign a Z value based on layer depth, with fringe = 0 as a special case
      layer["z"] = (index - fringe_index) * 10.0
    end

    objs
  end

  # Load a TMX file and calculate the objects inside including the
  # Spritesheet and Spritestack. Do not assume this TMX file obeys any
  # particular additional conventions beyond basic TMX format.
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
        image: tileset.image,
        imagewidth: tileset.imagewidth,
        imageheight: tileset.imageheight,
        tilewidth: tileset.tilewidth,
        tileheight: tileset.tileheight,
        oversize: tileset.tilewidth != tiles.tilewidth || tileset.tileheight != tiles.tileheight,
        spacing: tileset.spacing,
        margin: tileset.margin,
        imagetrans: tileset.imagetrans, # Currently unused, color to treat as transparent
        properties: tileset.properties,
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

    { filename: filename, tmx_name: File.basename(filename).split(".")[0], spritesheet: spritesheet, spritestack: spritestack, objects: objects }
  end

  # Find the animations included in the TMX file
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
