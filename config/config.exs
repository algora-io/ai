# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :algora,
  title: "Algora AI",
  description: "✨ Bounty and developer recommendations",
  ecto_repos: [Algora.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :algora, AlgoraWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AlgoraWeb.ErrorHTML, json: AlgoraWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Algora.PubSub,
  live_view: [signing_salt: "wLI6vcHC"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :algora, Algora.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  algora: [
    args:
      ~w(js/app.ts --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.0",
  algora: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :nanoid,
  size: 16,
  alphabet: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

config :ex_money,
  default_cldr_backend: Algora.Cldr

config :ex_cldr,
  default_locale: "en",
  default_backend: Algora.Cldr

# SaladUI use tails to properly merge Tailwind CSS classes
config :tails,
  color_classes: [
    "primary",
    "secondary",
    "destructive",
    "success",
    "muted",
    "accent",
    "popover",
    "card",
    "border",
    "input",
    "ring",
    "background",
    "foreground",
    "gray"
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
