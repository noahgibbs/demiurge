module Demiurge;end

# The Errors module exists to scope errors out of the top-level namespace.
module Demiurge::Errors
  # Demiurge::Errors::Exception is the parent class of all Demiurge-specific
  # Exceptions.
  #
  # @since 0.0.1
  class Exception < ::RuntimeError
    # @return [Hash] Additional specific data about this exception.
    # @since 0.0.1
    attr_reader :info

    # Optionally add a hash of extra data, called info, to this exception.
    #
    # @param msg [String] The message for this Exception
    # @since 0.0.1
    def initialize(msg, info = {})
      super(msg)
      @info = info
    end

    # Serialize this exception to a JSON-serializable PORO.
    #
    # @return [Hash] The serialized {Demiurge::Errors::Exception} data
    # @since 0.0.1
    def jsonable()
      {
        "message" => self.message,
        "info" => self.info,
        "backtrace" => self.backtrace
      }
    end
  end

  # A RetryableError or its subclasses normally indicate an error that
  # is likely to be transient, and where retrying the tick is a
  # reasonable attempt at a solution.
  #
  # @since 0.0.1
  class RetryableError < ::Demiurge::Errors::Exception; end

  # A BadScriptError will normally not benefit from retrying. Instead,
  # one or more scripts associated with this error is presumed to be
  # bad or outdated. The primary thing to do with BadScriptErrors is
  # to accumulate and count them and possibly to deactivate one or
  # more bad scripts. Error counting can allow an administrator to
  # locate (or guess) the bad script in question and disable one or
  # more scripts to remove the problem. While it's technically
  # possible to disable bad scripts automatically, that may sometimes
  # have distressing side effects when a script was intended to run
  # and didn't. It may also have false positives where a misbehaving
  # script "frames" a correct script by causing errors downstream.
  #
  # @since 0.0.1
  class BadScriptError < ::Demiurge::Errors::Exception; end

  # This exception occurs when trying to use an action that doesn't
  # exist, such as from {Demiurge::ActionItem#run_action} or
  # {Demiurge::Agent#queue_action}.
  #
  # @since 0.0.1
  class NoSuchActionError < BadScriptError; end

  # This exception occurs when trying to use an agent name that
  # doesn't belong to any registered agent.
  #
  # @since 0.0.1
  class NoSuchAgentError < BadScriptError; end

  # This occurs when trying to use a nonexistent state key in a way
  # that isn't allowed.  This exception normally refers to object
  # state, when accessed from a script.
  #
  # @since 0.0.1
  class NoSuchStateKeyError < BadScriptError; end

  # This occurs when trying to modify or cancel an intention when
  # there isn't one.
  #
  # @since 0.0.1
  class NoCurrentIntentionError < BadScriptError; end

  # This occurs if intentions queue other, new intentions too many
  # times in the same tick. The exception exists to prevent infinite
  # loops of queued intentions. If your script wants to queue lots of
  # intentions, consider queueing them during *later* ticks instead of
  # immediately.
  #
  # @since 0.0.1
  class TooManyIntentionLoopsError < BadScriptError; end

  # This occurs if notifications queue other, new notifications too
  # many times in the same tick. The exception exists to prevent
  # infinite loops of queued notifications. If your script wants to
  # queue lots of notifications, consider queueing them after the tick
  # has finished, perhaps on a later tick.
  #
  # @since 0.0.1
  class TooManyNotificationLoopsError < BadScriptError; end
end
