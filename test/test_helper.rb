$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'demiurge'
require 'demiurge/tmx'

require 'minitest/autorun'

class Minitest::Test
  def assert_hash_contains_fields(h, notification)
    wrong = h.any? { |k, v| notification[k] != v }
    assert !wrong, "Structure doesn't contain the correct fields! Required: #{h.inspect}, Supplied: #{notification.inspect}."
  end
end
