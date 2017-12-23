module Demiurge

  # An Intention is an unresolved event. Some part of the simulated
  # world "wishes" to take an action. This need not be a sentient
  # being - any change to the world should occur with an Intention
  # then being resolved into changes in state and events -- or
  # not. It's also possible for an intention to resolve to nothing at
  # all. For instance, an intention to move in an impossible direction
  # could simply resolve with no movement, no state change and no event.
  #
  # Intentions go through verification, resolution and eventually
  # notification.
  #
  # Intentions are not, in general, serializable. They normally
  # persist for only a single tick. To persist an intention for most StateItems,
  # consider persisting action names instead.
  #
  # For more details about Intention, see {file:CONCEPTS.md}.
  #
  # @since 0.0.1

  class Intention
    # Subclasses of intention can require all sorts of constructor arguments to
    # specify what the intention is. But the engine should always be supplied.
    #
    # @param engine [Demiurge::Engine] The engine this Intention is part of.
    # @since 0.0.1
    def initialize(engine)
      @cancelled = false
      @engine = engine
    end

    # This cancels the intention, and gives the reason for the
    # cancellation.
    #
    # @param reason [String] A human-readable reason this action was cancelled
    # @param info [Hash] A String-keyed Hash of additional information about the cancellation
    # @return [void]
    # @since 0.0.1
    def cancel(reason, info = {})
      @cancelled = true
      @cancelled_by = caller(1, 1)
      @cancelled_reason = reason
      @cancelled_info = info
      cancel_notification
      nil
    end

    # Most intentions will send a cancellation notice when they are
    # cancelled. By default, this will include who cancelled the
    # intention and why.  If the cancellation info Hash includes
    # "silent" with a true value, by default no notification will be
    # sent out. This is to avoid an avalache of notifications for
    # common cancelled intentions that happen nearly every
    # tick. {#cancel_notification} can be overridden by child classes
    # for more specific cancel notifications.
    #
    # @return [void]
    # @since 0.0.1
    def cancel_notification
      # "Silent" notifications are things like an agent's action queue
      # being empty so it cancels its intention.  These are normal
      # operation and nobody is likely to need notification every
      # tick that they didn't ask to do anything so they didn't.
      return if @cancelled_info && @cancelled_info["silent"]
      @engine.send_notification({
                                  :reason => @cancelled_reason,
                                  :by => @cancelled_by,
                                  :id => @intention_id,
                                  :intention_type => self.class.to_s,
                                  :info => @cancelled_info
                                },
                                type: "intention_cancelled", zone: "admin", location: nil, actor: nil)
    end

    # This returns whether this intention has been cancelled.
    #
    # @return [Boolean] Whether the notification is cancelled.
    def cancelled?
      @cancelled
    end

    # This method allows child classes of Intention to check whether
    # they should happen at all. If this method returns false, the
    # intention will self-cancel without sending a notification and
    # quietly not occur. The method exists primarily to allow
    # "illegal" intentions like walking through a wall or drinking
    # nonexistent water to quietly not happen without the rest of the
    # simulation responding to them in any way.
    #
    # @return [Boolean] If this method returns false, the Intention will quietly self-cancel before the offer phase.
    # @since 0.0.1
    def allowed?
      raise "Unimplemented 'allowed?' for intention: #{self.inspect}!"
    end

    # This method tells the Intention that it has successfully
    # occurred and it should modify StateItems accordingly. Normally
    # this will only be called after {#allowed?} and {#offer} have
    # completed, and other items have had a chance to modify or cancel
    # this Intention.
    #
    # @return [void]
    # @since 0.0.1
    def apply
      raise "Unimplemented 'apply' for intention: #{self.inspect}!"
    end

    # When an Intention is "offered", that means appropriate other
    # entities have a chance to modify or cancel the intention. For
    # instance, a movement action in a room should be offered to that
    # room, which may trigger a special action (e.g. trap) or change
    # the destination of the action (e.g. exits, slippery ice,
    # spinning spaces.)
    #
    # @see file:CONCEPTS.md
    # @param intention_id [Integer] The intention ID that Demiurge has assigned to this Intention
    # @return [void]
    # @since 0.0.1
    def offer(intention_id)
      raise "Unimplemented 'offer' for intention: #{self.inspect}!"
    end

    # This is a normally-private part of the Tick cycle. It checks the
    # {#allowed?} and {#offer} phases for this one specific Intention.
    #
    # @return [void]
    # @since 0.0.1
    def try_apply(intention_id)
      @intention_id = intention_id
      unless allowed?
        # Certain intentions can send an "intention failed" notification.
        # Such a notification would be sent from here.
        return
      end
      offer(intention_id)
      return if cancelled? # Notification should already have been sent out
      apply
      nil
    end
  end
end
