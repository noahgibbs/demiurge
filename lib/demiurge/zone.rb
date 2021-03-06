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

  class Zone < Container
    # A Zone isn't located "inside" somewhere else. It is located in/at itself.
    #
    # @return [Demiurge::StateItem] The zone's item
    # @since 0.0.1
    def location
      self
    end

    # A Zone isn't located "inside" somewhere else. It is located in/at itself.
    #
    # @return [String] The zone's name
    # @since 0.0.1
    def location_name
      @name
    end

    # Similarly, a Zone has no position beyond itself.
    #
    # @return [String] The zone's name, which is also its position string
    # @since 0.0.1
    def position
      @name
    end

    # A Zone's zone is itself.
    #
    # @return [Demiurge::StateItem] The Zone item
    # @since 0.0.1
    def zone
      self
    end

    # A Zone's zone is itself.
    #
    # @return [String] The Zone's item name
    # @since 0.0.1
    def zone_name
      @name
    end

    # A Zone is, indeed, a Zone.
    #
    # @return [Boolean] Return true for Zone and its subclasses.
    # @since 0.0.1
    def zone?
      true
    end

    # By default, a zone just passes control to all its non-agent
    # items, gathering up their intentions into a list. It doesn't ask
    # agents since agents located directly in zones are usually only
    # for instantiation.
    #
    # @return [Array<Demiurge::Intention>] The array of intentions for the next tick
    # @since 0.0.1
    def intentions_for_next_step
      intentions = @state["contents"].flat_map do |item_name|
        item = @engine.item_by_name(item_name)
        item.agent? ? [] : item.intentions_for_next_step
      end
      intentions
    end
  end
end
