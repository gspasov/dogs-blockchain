defmodule Call do

  alias Aecore.Keys.Worker, as: Keys

  @type call :: %{
    caller_address: binary(),
    caller_nonce: integer(),
    height: integer(),
    contract_address: binary(),
    gas_price: non_neg_integer(),
    gas_used: non_neg_integer(),
    return_value: binary(),
    return_type: :ok | :error | :revert
  }

end
