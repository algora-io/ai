import Ecto.Query
import Ecto.Changeset

IEx.configure(inspect: [charlists: :as_lists, limit: :infinity])

defmodule Helpers do
  def r(), do: IEx.Helpers.recompile()
end

import Helpers
