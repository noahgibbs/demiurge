module Demiurge
  # Notifications use string identifiers as names. It's legal to use
  # strings directly, but then typos can go undetected.  This also
  # serves as a list of what notifications are normally
  # available. Application-specific notifications should define their
  # own notification constants, either in this module or another one.
  #
  # @since 0.2.0
  module Notifications

    # This notification is sent when something is misconfigured, but
    # not in a continuity-threatening way.
    #
    # @since 0.2.0
    AdminWarning = "admin_warning"

    # This notification indicates that a tick has completed.
    #
    # @since 0.2.0
    TickFinished = "tick finished"

    # This notification indicates that a new item has been registered
    # by the engine.
    #
    # @since 0.2.0
    NewItem = "new item"

    # This notification means that state loading has begun into an
    # initialized engine.
    #
    # @since 0.2.0
    LoadStateStart = "load_state_start"

    # This notification means that state loading has finished in an
    # initialized engine.
    #
    # @since 0.2.0
    LoadStateEnd = "load_state_end"

    # This notification is sent when a World File reload is preparing
    # to start.  This will be sent on verify-only reloads as well as
    # normal reloads.
    #
    # @since 0.2.0
    LoadWorldVerify = "load_world_verify"

    # This notification is sent when a World File reload has
    # successfully verified and has begun loading. Verify-only reloads
    # do not send this signal.
    #
    # @since 0.2.0
    LoadWorldStart = "load_world_start"

    # This notification is sent when a World File reload has
    # successfully completed. Verify-only reloads do not send this
    # signal.
    #
    # @since 0.2.0
    LoadWorldEnd = "load_world_end"

    # This notification is sent when an agent moves between positions,
    # locations and/or zones. This notification goes out at the old
    # location and zone, which may be the same as the new.
    #
    # Fields: new_position (String), old_position (String), new_location (String), old_location (String), zone (String)
    #
    # @since 0.2.0
    MoveFrom = "move_from"

    # This notification is sent when an agent moves between positions,
    # locations and/or zones. This notification goes out at the new
    # location and zone, which may be the same as the old.
    #
    # Fields: new_position (String), old_position (String), new_location (String), old_location (String), zone (String)
    #
    # @since 0.2.0
    MoveTo = "move_to"

    # This notification is sent when an intention has been cancelled.
    #
    # Fields: reason (String), by (Array<String>), id (Integer), intention_type (String), info (Hash)
    #
    # @since 0.2.0
    IntentionCancelled = "intention_cancelled"

    # This notification is sent when an intention is successfully applied.
    #
    # Fields: id (Integer), intention_type (String), info (Hash)
    #
    # @since 0.2.0
    IntentionApplied = "intention_applied"
  end
end
