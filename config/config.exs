import Config
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

username = System.get_env("USERNAME")
password = System.get_env("PASSWORD")

config :shiny_barnacle, username: username, password: password
