module Demiurge
  # A Zone is a top-level location. It may (or may not) contain
  # various sub-locations managed by the top-level zone, and it may be
  # quite large or quite small. Zones are the "magic" by which
  # Demiurge permits simulation of much larger areas than CPU allows,
  # up to and including "infinite" procedural areas where only a small
  # portion is continuously simulated.

  # A simplistic engine may contain only a small number of top-level
  # areas, each a zone in itself. A complex engine may have a small
  # number of areas, but each does extensive managing of its
  # sub-locations.

  class Zone < ActionItem
    # By default, a zone just passes control to all its locations.
    def intentions_for_next_step(options = {})
      intentions = @engine.state_for_property(@name, "location_names").flat_map do |loc_name|
        @engine.item_by_name(loc_name).intentions_for_next_step
      end
      intentions
    end
  end
end
