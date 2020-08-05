defmodule ShinyBarnacle.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [ShinyBarnacle.Worker]

    opts = [strategy: :one_for_one, name: ShinyBarnacle.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
