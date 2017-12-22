module Demiurge

  # Sometimes you just want state that sits and does nothing unless
  # you mess with it. Player password hashes? Top-level game settings?
  # Heck, even something sort-of-active like bank inventory can make
  # sense to model this way since it will never do anything on its
  # own. This is especially good for things that will never interact
  # with the engine cycle - something that ignores ticks, intentions,
  # notifications, etc.
  #
  # @since 0.0.1
  class InertStateItem < StateItem
    # An InertStateItem doesn't intend anything, ever.
    #
    # @return [Array<Intention>] This array will always be empty for an InertStateItem
    # @since 0.0.1
    def intentions_for_next_step(*args)
      []
    end
  end
end
