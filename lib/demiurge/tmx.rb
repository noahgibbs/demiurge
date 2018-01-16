require "tmx"  # Require the TMX gem

module Demiurge

  # Demiurge::Tmx is the module for Tmx internals. This includes Tmx
  # parsing, caching and general encapsulation.
  #
  # TMX support here includes basic/normal TMX support for products of
  # the Tiled map editor (see "http://mapeditor.org" and
  # "http://docs.mapeditor.org/en/latest/reference/tmx-map-format/") and
  # more complex tiled map support for formats based on the ManaSource
  # game engine, including variants like Source of Tales, Land of Fire,
  # The Mana World and others. For more information on the ManaSource
  # mapping format, see "http://doc.manasource.org/mapping.html".
  #
  # In general, Tiled and "raw" TMX try to be all things to all
  # games. If you can use a tile editor for it, Tiled would like to do
  # that for you. ManaSource is a more specialized engine and
  # introduces new concepts like named "Fringe" layers to make it clear
  # how a humanoid sprite walks through the map, named "Collision"
  # layers for walkability and swimmability, known-format "objects" for
  # things like doors, warps, NPCs, NPC waypoints and monster spawns.
  # Not all of that will be duplicated in Demiurge, but support for such
  # things belongs in the ManaSource-specific TMX parsing code.
  #
  # In the long run, it's very likely that there will be other TMX
  # "dialects" like ManaSource's. Indeed, Demiurge might eventually
  # specify its own TMX dialect to support non-ManaSource features like
  # procedural map generation. My intention is to add them in the same
  # way - they may be requested in the Demiurge World files in the DSL,
  # and they will be an additional parsing pass on the result of "basic"
  # TMX parsing.
  #
  # @todo This entire file feels like a plugin waiting to
  #   happen. Putting it into Demiurge and monkeypatching seems slightly
  #   weird and "off". There's nothing wrong with having TiledLocation
  #   in Demiurge, and we do. But TMX, specifically, has a lot of
  #   format-specific stuff that doesn't seem to belong in core
  #   Demiurge. That's part of why it's off by itself in a separate
  #   file. If we were to support a second tilemap format, that would
  #   definitely seem to belong in a plugin. It's not clear what makes
  #   TMX different other than it being the first supported map format.
  #   The only thing keeping this from being the "demiurge-tmx" gem is
  #   that I feel like the code is already diced too finely into gems
  #   for its current level of maturity.
  #
  # @since 0.3.0
  module Tmx; end

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
        @state["tile_layout_filename"] = tmx_spec
        @state["tile_layout_type"] = "tmx"
      end

      # Specify a TMX file as the tile layout, and interpret it according to ManaSource TMX conventions.
      def manasource_tile_layout(tmx_spec)
        @state["tile_layout_filename"] = tmx_spec
        @state["tile_layout_type"] = "manasource"
      end

      # Validate built_item before returning it
      def built_item
        raise("A TMX location (name: #{@name.inspect}) must have a tile layout!") unless @state["tile_layout_filename"]
        item = super
        item.tile_cache_entry  # Load the cache entry, make sure it works without error
        item
      end
    end
  end

  # A TmxLocation is a special location that is attached to a tile
  # layout, a TMX file. This affects the size and shape of the room,
  # and how agents may travel through it. TmxLocations have X and Y
  # coordinates (grid coordinates) for their positions.
  #
  # @since 0.2.0
  class Tmx::TmxLocation < TiledLocation
    # Get the default tile cache for newly-created
    # TmxLocations. Demiurge provides one by default which can be
    # overridden.
    #
    # @return [DemiurgeTmx::TileCache] The current default TileCache for newly-created TmxLocations
    # @since 0.3.0
    def self.default_cache
      @default_cache ||= ::Demiurge::Tmx::TmxCache.new
      @default_cache
    end

    # Set the default cache for newly-created TmxLocations.
    #
    # @param cache [Demiurge::Tmx::TileCache] The tile cache for all subsequently-created TmxLocations
    # @since 0.3.0
    def self.set_default_cache(cache)
      @default_cache = cache
    end

    # Set the tile cache for this specific TmxLocation
    #
    # @param cache [Demiurge::Tmx::TileCache]
    # @since 0.3.0
    def set_cache(cache)
      @cache = cache
    end

    # Get the tile cache for this Tmxlocation
    #
    # @return [Demiurge::Tmx::TileCache]
    # @since 0.3.0
    def cache
      @cache ||= self.class.default_cache
    end

    # Let's resolve any exits that go to other TMX locations.
    #
    # @since 0.3.0
    def finished_init
      super
      exits = []
      return unless @state["tile_layout_type"] == "manasource"

      # Go through the contents looking for locations
      zone_contents = self.zone.contents

      # ManaSource locations often store exits as objects in an
      # object layer.  They don't cope with multiple locations that
      # use the same TMX file since they identify the destination by
      # the TMX filename.  In Demiurge, we don't let them cross zone
      # boundaries to avoid unexpected behavior in other folks'
      # zones.
      tile_cache_entry["objects"].select { |obj| obj["type"].downcase == "warp" }.each do |obj|
        next unless obj["properties"]
        dest_map_name = obj["properties"]["dest_map"]
        dest_location = zone_contents.detect { |loc| loc.is_a?(::Demiurge::Tmx::TmxLocation) && loc.tile_cache_entry["tmx_name"] == dest_map_name }
        if dest_location
          entry = dest_location.tile_cache_entry
          dest_position = "#{dest_location.name}##{obj["properties"]["dest_x"]},#{obj["properties"]["dest_y"]}"
          src_x_coord = obj["x"] / tile_cache_entry["tilewidth"]
          src_y_coord = obj["y"] / tile_cache_entry["tileheight"]
          src_position = "#{name}##{src_x_coord},#{src_y_coord}"
          raise("Exit destination position #{dest_position.inspect} loaded from TMX location #{name.inspect} (TMX: #{tile_cache_entry["filename"]}) is not valid!") unless dest_location.valid_position?(dest_position)
          exits.push({ src_loc: self, src_pos: src_position, dest_pos: dest_position })
        else
          @engine.admin_warning "Unresolved TMX exit in #{name.inspect}: #{obj["properties"].inspect}!",
                                "location" => name, "properties" => obj["properties"]
        end
      end

      exits.each do |exit|
        exit[:src_loc].add_exit(from: exit[:src_pos], to: exit[:dest_pos])
      end
    end

    # This checks the coordinate's validity, but not relative to any
    # specific person/item/whatever that could occupy the space.
    #
    # @return [Boolean] Whether the coordinate is valid
    # @since 0.2.0
    def valid_coordinate?(x, y)
      return false if x < 0 || y < 0
      return false if x >= tile_cache_entry["width"] || y >= tile_cache_entry["height"]
      return true unless tile_cache_entry["collision"]
      return tile_cache_entry["collision"][y * tile_cache_entry["width"] + x] == 0
    end

    # Determine whether this coordinate location can accommodate a
    # rectangular item of the given coordinate dimensions.
    #
    # @since 0.2.0
    def can_accomodate_dimensions?(left_x, upper_y, width, height)
      return false if left_x < 0 || upper_y < 0
      right_x = left_x + width - 1
      lower_y = upper_y + height - 1
      return false if right_x >= tile_cache_entry["width"] || lower_y >= tile_cache_entry["height"]
      return true unless tile_cache_entry["collision"]
      (left_x..right_x).each do |x|
        (upper_y..lower_y).each do |y|
          return false if tile_cache_entry["collision"][y * tile_cache_entry["width"] + x] != 0
        end
      end
      return true
    end

    # For a TmxLocation's legal position, find somewhere not covered
    # as a collision on the collision map.
    #
    # @return [String] A legal position string within this location
    # @since 0.2.0
    def any_legal_position
      entry = tile_cache_entry
      if entry["collision"]
        # We have a collision layer? Fabulous. Scan upper-left to lower-right until we get something non-collidable.
        (0...entry["width"]).each do |x|
          (0...entry["height"]).each do |y|
            if entry["collision"][y * tile_cache_entry["width"] + x] == 0
              # We found a walkable spot.
              return "#{@name}##{x},#{y}"
            end
          end
        end
        # If we got here, there exists no walkable spot in the whole location.
      end
      # Screw it, just return the upper left corner.
      return "#{@name}#0,0"
    end

    # Return the tile object for this location
    def tile_cache_entry
      raise("A TMX location (name: #{@name.inspect}) must have a tile layout!") unless state["tile_layout_filename"]
      cache.tmx_entry(@state["tile_layout_type"], @state["tile_layout_filename"])
    end

    # Return a TMX object's structure, for an object of the given name, or nil.
    def tmx_object_by_name(name)
      tile_cache_entry["objects"].detect { |o| o["name"] == name }
    end

    # Return the tile coordinates of the TMX object with the given name, or nil.
    def tmx_object_coords_by_name(name)
      obj = tmx_object_by_name(name)
      return nil unless obj
      [ obj["x"] / tile_cache_entry["tilewidth"], obj["y"] / tile_cache_entry["tileheight"] ]
    end

  end
end

Demiurge::DSL::TopLevelBuilder.register_type "TmxLocation", Demiurge::Tmx::TmxLocation

module Demiurge::Tmx
  # A TmxCache loads and remembers TMX file maps from the tmx gem. For
  # a variety of reasons, it's not great to reload TMX files every
  # time we need to know about them, but it can also be a problem to
  # store a copy of the parsed version every time and place we use it.
  # Caching is, of course, a time-honored solution to this problem.
  #
  # @since 0.3.0
  class TmxCache
    # @return [String] Root directory the cache was created relative to
    attr_reader :root_dir

    # Create the TmxCache
    #
    # @param options [Hash] Options
    # @option options [String] :root_dir The root directory to read TMX and TSX files relative to
    def initialize(options = {})
      @root_dir = options[:root_dir] || Dir.pwd
    end

    def tmx_entry(layout_type, layout_filename)
      @tile_cache ||= {}
      @tile_cache[layout_type] ||= {}
      if @tile_cache[layout_type][layout_filename]
        return @tile_cache[layout_type][layout_filename]
      end

      if layout_type == "manasource"
        @tile_cache[layout_type][layout_filename] = sprites_from_manasource_tmx(layout_filename)
      elsif layout_type == "tmx"
        @tile_cache[layout_type][layout_filename] = sprites_from_tmx(layout_filename)
      else
        raise "A TMX location must have a known type of layout (tmx or manasource), not #{layout_type.inspect}!"
      end

      @tile_cache[layout_type][layout_filename]
    end

    # This is to support TMX files for ManaSource, ManaWorld, Land of
    # Fire, Source of Tales and other Mana Project games. It can't be
    # perfect since there's some variation between them, but it can
    # follow most major conventions.

    # Load a TMX file and calculate the objects inside including the
    # Spritesheet and Spritestack. Assume this TMX file obeys ManaSource
    # conventions such as fields for exits and names for layers.
    def sprites_from_manasource_tmx(filename)
      entry = sprites_from_tmx filename

      stack_layers = entry["map"]["layers"].select { |layer| layer["type"] == "tilelayer" }

      # Remove the collision layer, add as separate collision top-level entry
      collision_index = stack_layers.index { |l| l["name"].downcase == "collision" }
      collision_layer = stack_layers.delete_at collision_index if collision_index

      # Some games make this true/false, others have separate visibility
      # or swimmability in it. In general, we'll just expose the data.
      entry["collision"] = collision_layer["data"] if collision_layer

      # Remove the heights layer, add as separate heights top-level entry
      heights_index = stack_layers.index { |l| ["height", "heights"].include?(l["name"].downcase)  }
      heights_layer = stack_layers.delete_at heights_index if heights_index
      entry["heights"] = heights_layer

      fringe_index = stack_layers.index { |l| l["name"].downcase == "fringe" }
      raise ::Demiurge::Errors::TmxFormatError.new("No Fringe layer found in ManaSource TMX File #{filename.inspect}!", "filename" => filename) unless fringe_index
      stack_layers.each_with_index do |layer, index|
        # Assign a Z value based on layer depth, with fringe = 0 as a special case
        layer["z"] = (index - fringe_index) * 10.0
      end

      entry
    end

    # Load a TMX file and JSONify it. This includes its various
    # tilesets, such as embedded tilesets and TSX files.  Do not
    # assume this TMX file obeys any particular additional conventions
    # beyond basic TMX format.
    def sprites_from_tmx(filename)
      cache_entry = {}

      # This recursively loads things like tileset .tsx files, so we
      # change to the root dir.
      Dir.chdir(@root_dir) do
        tmx_map = Tmx.load filename
        filename.sub!(/\.tmx\Z/, ".json")
        cache_entry["map"] = MultiJson.load(tmx_map.export_to_string(:filename => filename, :format => :json))
      end

      tiles = cache_entry["map"]
      cache_entry["tilesets"] = tiles["tilesets"]

      # Add entries to the top-level cache entry, but not inside the "map" structure
      cache_entry["tmx_name"] = File.basename(filename).split(".")[0]
      cache_entry["name"] = tiles["name"] || cache_entry["tmx_name"]
      cache_entry["filename"] = filename
      cache_entry["animations"] = animations_from_tilesets cache_entry["tilesets"]
      cache_entry["objects"] = tiles["layers"].flat_map { |layer| layer["objects"] || [] }

      # Copy most-used properties into top-level cache entry
      ["width", "height", "tilewidth", "tileheight"].each do |property|
        cache_entry[property] = tiles[property]
      end

      cache_entry
    end

    # Find the animations included in the TMX file
    def animations_from_tilesets tilesets
      tilesets.flat_map do |tileset|
        (tileset["tiles"] || []).map do |tile|
          p = tile["properties"]
          if p && p["animation-frame0"]
            section = 0
            anim = []

            while p["animation-frame#{section}"]
              section_hash = {
                "frame" => p["animation-frame#{section}"].to_i + tileset[:firstgid],
                "duration" => p["animation-delay#{section}"].to_i
              }
              anim.push section_hash
              section += 1
            end
            { "tile_anim_#{tile["id"].to_i + tileset[:firstgid]}" => anim }
          else
            nil
          end
        end.compact
      end.inject({}, &:merge)
    end
  end
end
