defmodule Mqttsn.Mixfile do
  use Mix.Project

  def project do
    [app: :mqttsn,
     version: "0.0.1",
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  def application do
    [applications: [:logger, :inets],
     env: [],
     mod: {Mqttsn, []}]
  end

  defp deps do
    []
  end
end
