require_relative 'test_helper'

class ItemNameTest < Minitest::Test
  def test_item_util_funcs
    engine = Demiurge.engine_from_dsl_text(["Item Name DSL", ""])

    assert_equal true, engine.valid_item_name?("abc")
    assert_equal true, engine.valid_item_name?("the-marquiz-de-sade")
    assert_equal true, engine.valid_item_name?("bobo and wade")
    assert_equal true, engine.valid_item_name?("sam_and_max")
    assert_equal false, engine.valid_item_name?(nil)
    assert_equal false, engine.valid_item_name?("")
    assert_equal false, engine.valid_item_name?("bob#spam")
    assert_equal false, engine.valid_item_name?("bob#25,37")
    assert_equal false, engine.valid_item_name?("bob$31")
  end
end
