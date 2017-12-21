$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'demiurge'
require 'demiurge/tmx'

require 'minitest/autorun'

class Minitest::Test
  def assert_engine_sanity_check_contents(engine)
    # Get all registered item names
    item_names = engine.all_item_names

    zones = engine.zones
    zone_contents = zones.flat_map { |z| z.contents_names }
    assert zone_contents.size == zone_contents.uniq.size, "Engine contains duplicate item references in top-level contents of zones!"

    traversed = []
    to_traverse = zone_contents
    loops = 0
    loop do
      next_level_names = to_traverse.flat_map { |name| item = engine.item_by_name(name); item.is_a?(Demiurge::Container) ? item.contents_names : [] }
      loops += 1
      assert loops <= 30, "Engine's contents are nested too deeply, probably recursive! #{next_level_names.inspect}"
      break if next_level_names == []   # Nothing new added or changed? Great, we're done.
      traversed += to_traverse
      to_traverse = next_level_names
    end

    no_dups = traversed.uniq
    if traversed.size != no_dups.size
      # @todo Identify the duplicated entries
      assert false, "Engine contains #{traversed.size - no_dups.size} duplicated contents entries! #{traversed.inspect}"
    end

    # @todo Go through all item names, make sure everything was either traversed or has no location
    # @todo Go through all engine items, make sure everything's location matches its contents entry
  end

  def assert_hash_contains_fields(h, notification)
    wrong = h.any? { |k, v| notification[k] != v }
    assert !wrong, "Structure doesn't contain the correct fields! Required: #{h.inspect}, Supplied: #{notification.inspect}."
  end
end
