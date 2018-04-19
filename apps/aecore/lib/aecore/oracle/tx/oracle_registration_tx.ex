defmodule Aecore.Oracle.Tx.OracleRegistrationTx do
  @moduledoc """
  Contains the transaction structure for oracle registration
  and functions associated with those transactions.
  """

  alias __MODULE__
  alias Aecore.Tx.DataTx
  alias Aecore.Account.Account
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Oracle.Oracle
  alias ExJsonSchema.Schema, as: JsonSchema
  alias Aecore.Chain.Chainstate
  alias Aecore.Account.AccountStateTree

  require Logger

  @type tx_type_state :: Chainstate.oracles()

  @type payload :: %{
          query_format: Oracle.json_schema(),
          response_format: Oracle.json_schema(),
          query_fee: non_neg_integer(),
          ttl: Oracle.ttl()
        }

  @type t :: %OracleRegistrationTx{
          query_format: map(),
          response_format: map(),
          query_fee: non_neg_integer(),
          ttl: Oracle.ttl()
        }

  defstruct [
    :query_format,
    :response_format,
    :query_fee,
    :ttl
  ]

  @spec get_chain_state_name() :: :oracles
  def get_chain_state_name, do: :oracles

  use ExConstructor

  @spec init(payload()) :: OracleRegistrationTx.t()
  def init(%{
        query_format: query_format,
        response_format: response_format,
        query_fee: query_fee,
        ttl: ttl
      }) do
    %OracleRegistrationTx{
      query_format: query_format,
      response_format: response_format,
      query_fee: query_fee,
      ttl: ttl
    }
  end

  @spec is_valid?(OracleRegistrationTx.t(), DataTx.t()) :: boolean()
  def is_valid?(
        %OracleRegistrationTx{
          query_format: query_format,
          response_format: response_format,
          ttl: ttl
        },
        data_tx
      ) do
    senders = DataTx.senders(data_tx)

    formats_valid =
      try do
        JsonSchema.resolve(query_format)
        JsonSchema.resolve(response_format)
        true
      rescue
        e ->
          Logger.error("Invalid query or response format definition - " <> inspect(e))

          false
      end

    cond do
      ttl <= 0 ->
        Logger.error("Invalid ttl")
        false

      !formats_valid ->
        false

      !Oracle.ttl_is_valid?(ttl) ->
        Logger.error("Invald ttl")
        false

      length(senders) != 1 ->
        Logger.error("Invalid senders number")
        false

      true ->
        true
    end
  end

  @spec process_chainstate!(
          ChainState.account(),
          Oracle.oracles(),
          non_neg_integer(),
          OracleRegistrationTx.t(),
          DataTx.t()
        ) :: {ChainState.accounts(), Oracle.oracles()}
  def process_chainstate!(
        accounts,
        %{registered_oracles: registered_oracles} = oracle_state,
        block_height,
        %OracleRegistrationTx{} = tx,
        data_tx
      ) do
    sender = DataTx.sender(data_tx)

    updated_registered_oracles =
      Map.put_new(registered_oracles, sender, %{tx: tx, height_included: block_height})

    updated_oracle_state = %{
      oracle_state
      | registered_oracles: updated_registered_oracles
    }

    {accounts, updated_oracle_state}
  end

  @spec preprocess_check!(
          ChainState.accounts(),
          Oracle.oracles(),
          non_neg_integer(),
          OracleRegistrationTx.t(),
          DataTx.t()
        ) :: :ok
  def preprocess_check!(
        accounts,
        %{registered_oracles: registered_oracles},
        block_height,
        tx,
        data_tx
      ) do
    sender = DataTx.sender(data_tx)
    fee = DataTx.fee(data_tx)

    cond do
      AccountStateTree.get(accounts, sender).balance - fee < 0 ->
        throw({:error, "Negative balance"})

      !Oracle.tx_ttl_is_valid?(tx, block_height) ->
        throw({:error, "Invalid transaction TTL"})

      Map.has_key?(registered_oracles, sender) ->
        throw({:error, "Account is already an oracle"})

      !is_minimum_fee_met?(tx, fee, block_height) ->
        throw({:error, "Fee too low"})

      true ->
        :ok
    end
  end

  @spec deduct_fee(ChainState.accounts(), OracleExtendTx.t(), DataTx.t(), non_neg_integer()) ::
          ChainState.account()
  def deduct_fee(accounts, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, data_tx, fee)
  end

  @spec is_minimum_fee_met?(OracleRegistrationTx.t(), non_neg_integer(), non_neg_integer()) ::
          boolean()
  def is_minimum_fee_met?(tx, fee, block_height) do
    case tx.ttl do
      %{ttl: ttl, type: :relative} ->
        fee >= calculate_minimum_fee(ttl)

      %{ttl: ttl, type: :absolute} ->
        if block_height != nil do
          fee >=
            ttl
            |> Oracle.calculate_relative_ttl(block_height)
            |> calculate_minimum_fee()
        else
          true
        end
    end
  end

  @spec calculate_minimum_fee(non_neg_integer()) :: non_neg_integer()
  defp calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]

    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_registration_base_fee]

    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end
end
