defmodule RomanticCollationTest do
  use ExUnit.Case, async: true
  doctest RomanticCollation

  test "natural, structural, and Latin ordering" do
    assert RomanticCollation.sort(["file10", "Apple", "file2", "apple"]) == [
             "apple",
             "Apple",
             "file2",
             "file10"
           ]

    assert RomanticCollation.compare("test with spaces", "test1") == :lt
    assert RomanticCollation.compare("n", "ñ") == :lt
    assert RomanticCollation.compare("ñ", "o") == :lt
  end

  test "equality is disclosed without changing binary identity" do
    assert RomanticCollation.equal?("ș", "ş")
    refute "ș" == "ş"
    assert RomanticCollation.sort(["ş", "ș"]) == ["ş", "ș"]
    assert RomanticCollation.equal?("10e0", "1e1", scientific: true)
  end

  test "options and arbitrary precision" do
    assert RomanticCollation.compare("VII", "IX", roman: true) == :lt
    assert RomanticCollation.compare("1.10", "1.9", decimal: true) == :lt
    assert RomanticCollation.compare("1e9999999999", "1e10000000000", scientific: true) == :lt
    assert RomanticCollation.key("Z", code_point: true) == <<?Z, 0>>
  end

  test "binary lengths and batch results" do
    data = [<<>>, <<0>>, <<0, 255, 0>>, "café"]
    assert RomanticCollation.keys(data) == Enum.map(data, &RomanticCollation.key/1)
    assert RomanticCollation.key(<<0, 255>>, 1) == <<0, 255, 0>>
    assert RomanticCollation.key(<<0>>) != RomanticCollation.key(<<>>)
  end

  test "long native calls and concurrent handle use" do
    input = String.duplicate("9", 20000)
    tasks = for _ <- 1..12, do: Task.async(fn -> RomanticCollation.key(input) end)
    expected = RomanticCollation.key(input)
    Enum.each(tasks, fn task -> assert Task.await(task, 10000) == expected end)
  end

  test "invalid arguments fail explicitly" do
    assert_raise ArgumentError, fn -> RomanticCollation.key("a", 128) end
    assert_raise ArgumentError, fn -> RomanticCollation.key("a", decimal: :yes) end
    assert_raise KeyError, fn -> RomanticCollation.key("a", unknown: true) end
    assert_raise ArgumentError, fn -> RomanticCollation.key(:not_a_binary) end
    assert_raise ArgumentError, fn -> RomanticCollation.keys(["a", :bad]) end
  end

  test "Unicode whitespace and punctuation remain structural before letters" do
    assert RomanticCollation.sort(["aa", "a—", "a\u2002"]) == ["a\u2002", "a—", "aa"]
    assert RomanticCollation.equal?("a ", "a\u2002")
    assert RomanticCollation.compare("a€", "aa") == :gt
    assert RomanticCollation.compare("a—", "aa", code_point: true) == :gt
  end
end
