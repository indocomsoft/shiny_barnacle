defmodule ShinyBarnacle do
  @moduledoc """
  Documentation for `ShinyBarnacle`.
  """

  @vafs_client_id "97F0D1CACA7D41DE87538F9362924CCB-184318"
  @query %{
    "response_type" => "code",
    "client_id" => @vafs_client_id,
    "resource" => "sg_edu_nus_oauth",
    "redirect_uri" => "https://myaces.nus.edu.sg:443/htd/htd"
  }
  @endpoint "https://vafs.nus.edu.sg/adfs/oauth2/authorize"
  @login_url @endpoint
             |> URI.parse()
             |> Map.put(:query, URI.encode_query(@query))
             |> URI.to_string()
  @submit_url "https://myaces.nus.edu.sg/htd/htd"

  require Logger

  @doc """
  Gets the JSESSIONID cookie value based on the given credential.

  Note that this function will automatically prepend `"nusstu\\"`.
  """
  @spec get_session_cookie(String.t(), String.t()) :: {:ok, String.t()} | {:error, any()}
  def get_session_cookie(username, password) when is_binary(username) and is_binary(password) do
    body =
      URI.encode_query(%{
        "UserName" => "nusstu\\#{username}",
        "Password" => password,
        "AuthMethod" => "FormsAuthentication"
      })

    with {:ok, %{headers: headers, status_code: 302}} <- HTTPoison.post(@login_url, body),
         {_, location} <- Enum.find(headers, fn {k, _} -> String.downcase(k) == "location" end),
         cookies <- update_cookies(%{}, headers),
         {:ok, %{headers: headers, status_code: 302}} <-
           HTTPoison.get(location, [{"Cookie", serialize_cookies(cookies)}]),
         {_, location} <- Enum.find(headers, fn {k, _} -> String.downcase(k) == "location" end),
         cookies <- update_cookies(cookies, headers),
         {:ok, %{headers: headers, status_code: 200}} <-
           HTTPoison.get(location, [{"Cookie", serialize_cookies(cookies)}]),
         cookies <- update_cookies(cookies, headers) do
      {:ok, cookies["JSESSIONID"]}
    else
      {:error, error} -> {:error, error}
      x -> {:error, x}
    end
  end

  @spec submit(String.t(), number(), bool(), bool()) :: :ok | {:error, HTTPoison.Error.t()}
  def submit(cookie, temp, has_symptom \\ false, family_has_symptom \\ false)
      when is_number(temp) and is_boolean(has_symptom) and is_boolean(family_has_symptom) and
             is_binary(cookie) do
    now = DateTime.now!("Asia/Singapore")

    formatted_date = NimbleStrftime.format(now, "%d/%m/%Y")

    data = %{
      "actionName" => "dlytemperature",
      "webdriverFlag" => "",
      "tempDeclOn" => formatted_date,
      "declFrequency" => now |> NimbleStrftime.format("%p") |> String.at(0),
      # "temperature" => temp,
      "symptomsFlag" => if(has_symptom, do: "Y", else: "N"),
      "familySymptomsFlag" => if(family_has_symptom, do: "Y", else: "N")
    }

    Logger.info("Submitting #{inspect(data)}")

    body = URI.encode_query(data)

    headers = [
      {"Cookie", serialize_cookies(%{"JSESSIONID" => cookie})},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    case HTTPoison.post(@submit_url, body, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        if String.contains?(body, "Health Status Declaration for") and
             String.contains?(body, "S.No") and String.contains?(body, formatted_date) do
          :ok
        else
          {:error, body}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  @spec update_cookies(map(), [{String.t(), String.t()}]) :: map()
  def update_cookies(old_cookies, headers) when is_map(old_cookies) and is_list(headers) do
    Enum.reduce(headers, old_cookies, fn {k, v}, acc ->
      if String.downcase(k) == "set-cookie" do
        %{key: key, value: value} = SetCookie.parse(v)
        Map.put(acc, key, value)
      else
        acc
      end
    end)
  end

  @spec serialize_cookies(map()) :: String.t()
  def serialize_cookies(cookies) when is_map(cookies) do
    Cookie.serialize(cookies)
  end
end
