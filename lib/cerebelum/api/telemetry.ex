defmodule Cerebelum.API.Telemetry do
  @moduledoc """
  PromEx metrics exporter for Cerebelum.

  Uses prom_ex to export Prometheus metrics from the BEAM VM, Phoenix,
  Ecto, and custom Cerebelum business metrics.
  """

  use PromEx, otp_app: :cerebelum

  alias PromEx.Plugins

  @impl PromEx
  def plugins do
    [
      {Plugins.Phoenix, endpoint: Cerebelum.API.Endpoint, router: Cerebelum.API.Router},
      Plugins.Ecto,
      Plugins.Beam,
      Plugins.Application,
      Cerebelum.Metrics
    ]
  end

  @impl PromEx
  def dashboards do
    []
  end
end
