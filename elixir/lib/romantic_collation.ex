defmodule RomanticCollation.Native do
  @moduledoc false
  @on_load :load_nif
  def load_nif do
    path =
      System.get_env("ROMANTIC_COLLATION_NIF") ||
        Path.join(to_string(:code.priv_dir(:romantic_collation)), "romantic_nif")

    :erlang.load_nif(String.to_charlist(path), 0)
  end

  def key(_binary, _options), do: :erlang.nif_error(:nif_not_loaded)
  def keys(_binaries, _options), do: :erlang.nif_error(:nif_not_loaded)
  def compare(_a, _b, _options), do: :erlang.nif_error(:nif_not_loaded)
end

defmodule RomanticCollation do
  @moduledoc """
  Reproducible collation through the Rust core, verified against the Zig oracle.

  Keys are opaque binaries for ordering revision 2. Equal collation keys may
  represent different source binaries; ordinary Elixir `==` remains unchanged.
  Invalid UTF-8 and embedded NULs are accepted as explicit-length binaries.
  Native computation runs on BEAM's dirty CPU schedulers.

      iex> RomanticCollation.sort(["file10", "file2"])
      ["file2", "file10"]
      iex> RomanticCollation.compare("VII", "IX", roman: true)
      :lt
  """
  @bits [code_point: 1, decimal: 8, decimal_comma: 16, scientific: 32, roman: 64]

  @doc "Build a binary sort key. Options are a keyword list or the C API bitmask."
  def key(binary, options \\ []), do: RomanticCollation.Native.key(binary, mask(options))

  @doc "Build keys in one native call, retaining input order."
  def keys(binaries, options \\ []), do: RomanticCollation.Native.keys(binaries, mask(options))

  @doc "Compare two binaries, returning :lt, :eq, or :gt."
  def compare(a, b, options \\ []), do: RomanticCollation.Native.compare(a, b, mask(options))

  @doc "Test collation equality, which can differ from binary identity."
  def equal?(a, b, options \\ []), do: compare(a, b, options) == :eq

  @doc "Sort with precomputed keys. Collation-equal values retain input order."
  def sort(binaries, options \\ []) do
    binaries
    |> Enum.zip(keys(binaries, options))
    |> Enum.sort_by(&elem(&1, 1))
    |> Enum.map(&elem(&1, 0))
  end

  defp mask(options) when is_integer(options) and options >= 0 and options < 128, do: options

  defp mask(options) when is_list(options) do
    Enum.reduce(options, 0, fn {name, value}, acc ->
      bit = Keyword.fetch!(@bits, name)

      case value do
        true -> Bitwise.bor(acc, bit)
        false -> Bitwise.band(acc, Bitwise.bnot(bit))
        _ -> raise ArgumentError, "collation options must be booleans"
      end
    end)
  end

  defp mask(_), do: raise(ArgumentError, "expected collation options or an unsigned 7-bit mask")
end
