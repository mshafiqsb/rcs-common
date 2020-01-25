require "test/unit"
require 'securerandom'

class BinaryPatchTest < Test::Unit::TestCase

  def test_string
    input = "string to be modified"
    output = "string modified"

    input.binary_patch "to be ", ""

    assert_equal output, input
  end

  def test_binary
    input = SecureRandom.random_bytes(16)
    search = input.slice(0..3)
    output = "1234" + input[4..-1]

    input.binary_patch search, "1234"

    assert_equal output, input
  end

  def test_binary_with_zero
    input = "this\x00and\x00that"
    search = "and"
    replace = ",\x00this\x00,"
    output = "this\x00,\x00this\x00,\x00that"

    input.binary_patch search, replace

    assert_equal output, input
  end

  def test_binary_with_regex
    input = SecureRandom.random_bytes(16)
    search = input.slice(0..3)
    output = '\&$1' + input[4..-1]

    input.binary_patch search, '\&$1'

    assert_equal output, input
  end

  def test_not_found
    input = "ciao"

    assert_raise MatchNotFound do
      input.binary_patch "miao", "bau"
    end
  end

  def test_with_offset
    input = "ciao miao bau"
    offset = 5
    string = "test"
    output = "ciao test bau"

    input.binary_patch_at_offset offset, string

    assert_equal output, input
  end

  def test_with_offset_out_of_bound
    input = "ciao bau"
    offset = 15
    string = "test"

    assert_raise OutOfBounds do
      input.binary_patch_at_offset offset, string
    end
  end

  def test_with_offset_too_long
    input = "ciao bau"
    offset = 5
    string = "test"

    assert_raise OutOfBoundsString do
      input.binary_patch_at_offset offset, string
    end
  end

  def test_add_at_offset
    input = "\x00\x00\x00\x00ciao miao bau"
    offset = 0
    value = 16
    output = "\x10\x00\x00\x00ciao miao bau"

    input.binary_add_at_offset offset, value

    assert_equal output, input
  end

  def test_add_at_offset_not_zero
    input = "ciao \x10\x00\x00\x00 miao bau"
    offset = 5
    value = 16
    output = "ciao \x20\x00\x00\x00 miao bau"

    input.binary_add_at_offset offset, value

    assert_equal output, input
  end

end