module Demiurge
  class Exception < ::RuntimeError
    attr_reader :info
    def initialize(msg, info = {})
      super(msg)
      @info = info
    end

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
  class RetryableError < ::Demiurge::Exception; end

  # A BadScriptError will normally not benefit from retrying. Instead,
  # one or more scripts associated with this error is presumed to be
  # bad or outdated. The primary thing to do here is to accumulate
  # these errors, possibly while treating the script as a no-op. This
  # can allow an administrator to locate (or guess) the bad script in
  # question and disable one or more scripts to remove the
  # problem. While it's technically possible to do this automatically,
  # that may sometimes have distressing side effects when a script was
  # intended to run and didn't.
  class BadScriptError < ::Demiurge::Exception; end

  # Types of Exceptions:

  # Trying to use an action that doesn't exist, such as from "action"
  # or "queue_action".
  class NoSuchActionError < BadScriptError; end

  # Trying to use an agent name that doesn't seem to belong to an agent.
  class NoSuchAgentError < BadScriptError; end

  # Trying to use a nonexistent state key in a way that isn't allowed.
  # This is for object state, when accessed from a script.
  class NoSuchStateKeyError < BadScriptError; end

  # Trying to modify or cancel an intention when there isn't one.
  class NoCurrentIntentionError < BadScriptError; end

  # This happens if intentions queue other, new intentions too many
  # times (around 20) in the same tick.  It exists to prevent infinite
  # loops of queued intentions. If your script wants to queue lots of
  # intentions, consider queueing them for *later* ticks, which has no
  # limit.
  class TooManyIntentionLoopsError < BadScriptError; end

  # This happens if notifications queue other, new notifications too
  # many times (around 20) in the same tick.  It exists to prevent
  # infinite loops of queued notifications. If your script wants to
  # queue lots of notifications, consider queueing them for *later*
  # ticks, which has no limit.
  class TooManyNotificationLoopsError < BadScriptError; end
end
