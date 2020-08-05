defmodule ShinyBarnacle.Worker do
  @credential_file "cred.dat"

  # Retry every 10s to see if we have a credential now
  @interval_no_credential 10_000

  # Submit within range of 35.9C to 37.1C
  @temperature_range 359..371

  # Allow for time drift by reducing the range of "AM" and "PM" by 600s = 10 minutes
  @time_drift_allowance_seconds 600

  # Range to submit in AM in ISO8601 format
  @am_range {"07:00:00", "11:59:59"}
  # Range to submit in PM in ISO8601 format
  @pm_range {"12:00:00", "23:59:59"}

  use GenServer

  require Logger

  # Server functionality

  @impl true
  def init(_) do
    state =
      with {:ok, data} <- File.read("./#{@credential_file}"),
           %{"username" => username, "password" => password} <- URI.decode_query(data) do
        Logger.info("Credential file found, using username #{username}")
        {username, password}
      else
        _ ->
          Logger.error(
            "Credential file cannot be used, please use `ShinyBarnacle.Worker.store_credential`"
          )

          nil
      end

    Logger.info(
      "Worker started, will perform first submission after #{@interval_no_credential} ms"
    )

    Process.send_after(self(), :submit, @interval_no_credential)
    {:ok, state}
  end

  @impl true
  def handle_call({:store, {username, password}}, _from, _state) do
    {:reply, :ok, {username, password}}
  end

  @impl true
  def handle_info(:submit, state = {username, password}) do
    {:ok, cookie} = ShinyBarnacle.get_session_cookie(username, password)
    :ok = ShinyBarnacle.submit(cookie, Enum.random(@temperature_range) / 10)
    schedule_update()
    {:noreply, state}
  end

  @impl true
  def handle_info(:submit, nil) do
    Logger.error(
      "Worker does not have credentials stored yet, will retry in #{@interval_no_credential} ms"
    )

    Process.send_after(self(), :submit, @interval_no_credential)
    {:noreply, nil}
  end

  def schedule_update do
    now = DateTime.now!("Asia/Singapore")

    [next_start_time, next_end_time] =
      if now.hour < 12 do
        # AM now, PM next
        {pm_start, pm_end} = @pm_range
        today_date = NimbleStrftime.format(now, "%Y-%m-%d")
        [today_date <> "T#{pm_start}+0800", today_date <> "T#{pm_end}+0800"]
      else
        # PM now, AM next
        {am_start, am_end} = @am_range
        tomorrow_date = now |> DateTime.add(86_400, :second) |> NimbleStrftime.format("%Y-%m-%d")
        [tomorrow_date <> "T#{am_start}+0800", tomorrow_date <> "T#{am_end}+0800"]
      end
      |> Enum.map(fn iso8601 ->
        {:ok, utc_datetime, 28800} = DateTime.from_iso8601(iso8601)
        DateTime.to_unix(utc_datetime)
      end)

    next_start_time = next_start_time + @time_drift_allowance_seconds
    next_end_time = next_end_time - @time_drift_allowance_seconds

    next_time_unix = Enum.random(next_start_time..next_end_time)
    now_unix = DateTime.to_unix(now)
    time_ms = (next_time_unix - now_unix) * 1000

    next_time_iso8601 =
      next_time_unix
      |> DateTime.from_unix!()
      |> DateTime.shift_zone!("Asia/Singapore")
      |> DateTime.to_iso8601()

    Logger.info("Scheduling the next run in #{time_ms / 1000} s = #{inspect(next_time_iso8601)}")

    Process.send_after(self(), :submit, time_ms)
  end

  # Client functionality

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @spec store_credential(String.t(), String.t()) :: :ok | no_return()
  def store_credential(username, password, store_in_file \\ false)
      when is_binary(username) and is_binary(password) and is_boolean(store_in_file) do
    GenServer.call(__MODULE__, {:store, {username, password}})

    if store_in_file do
      data = URI.encode_query(%{"username" => username, "password" => password})
      File.write!("./#{@credential_file}", data)
      Logger.info("Stored credential in #{@credential_file}")
    end
  end
end
