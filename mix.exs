defmodule Mix.Tasks.Compile.RomanticNif do
  use Mix.Task.Compiler
  @recursive true

  @impl true
  def run(_args) do
    extension = if match?({:win32, _}, :os.type()), do: ".dll", else: ".so"

    source =
      case System.get_env("ROMANTIC_COLLATION_NIF") do
        nil ->
          link = Path.expand(Path.join(Mix.Project.build_path(), "romantic-native"))

          {log, status} =
            System.cmd("nix", ["build", "#{__DIR__}#elixir-nif", "--out-link", link],
              stderr_to_stdout: true
            )

          if status != 0, do: Mix.raise("Nix NIF build failed:\n#{log}")
          Path.join(link, "lib/romantic_nif" <> extension)

        path ->
          path <> extension
      end

    unless File.regular?(source), do: Mix.raise("NIF artifact is missing: #{source}")
    File.mkdir_p!("priv")
    destination = Path.join("priv", "romantic_nif" <> extension)

    case File.lstat(destination) do
      {:ok, %{type: :symlink}} ->
        if File.read_link!(destination) != source do
          File.rm!(destination)
          File.ln_s!(source, destination)
        end

      {:error, :enoent} ->
        File.ln_s!(source, destination)

      {:ok, _} ->
        Mix.raise("Refusing to overwrite an unmanaged NIF artifact: #{destination}")

      {:error, reason} ->
        Mix.raise("Cannot inspect NIF artifact: #{inspect(reason)}")
    end

    {:ok, []}
  end
end

defmodule RomanticCollation.MixProject do
  use Mix.Project

  def project do
    [
      app: :romantic_collation,
      version: "0.1.0",
      elixir: ">= 1.15.0",
      elixirc_paths: ["elixir/lib"],
      test_paths: ["elixir/test"],
      compilers: [:romantic_nif] ++ Mix.compilers(),
      deps: []
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
