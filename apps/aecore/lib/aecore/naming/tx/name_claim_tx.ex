defmodule Aecore.Naming.Tx.NameClaimTx do
  @moduledoc """
  Aecore structure of naming claim.
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Chain.ChainState
  alias Aecore.Naming.Tx.NameClaimTx
  alias Aecore.Naming.Naming
  alias Aecore.Account.Account
  alias Aecore.Naming.NameUtil
  alias Aecore.Account.AccountStateTree

  require Logger

  @typedoc "Expected structure for the Claim Transaction"
  @type payload :: %{
          name: String.t(),
          name_salt: Naming.salt()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of NameClaimTx we have the naming subdomain chainstate."
  @type tx_type_state() :: ChainState.naming()

  @typedoc "Structure of the Spend Transaction type"
  @type t :: %NameClaimTx{
          name: String.t(),
          name_salt: Naming.salt()
        }

  @doc """
  Definition of Aecore NameClaimTx structure

  ## Parameters
  - name: name to be claimed
  - name_salt: salt that the name was pre-claimed with
  """
  defstruct [:name, :name_salt]
  use ExConstructor

  # Callbacks

  @spec init(payload()) :: NameClaimTx.t()
  def init(%{name: name, name_salt: name_salt} = _payload) do
    %NameClaimTx{name: name, name_salt: name_salt}
  end

  @doc """
  Checks name format
  """
  @spec is_valid?(NameClaimTx.t()) :: boolean()
  def is_valid?(%NameClaimTx{name: name, name_salt: name_salt}) do
    name_valid =
      case NameUtil.normalize_and_validate_name(name) do
        {:ok, _} -> true
        {:error, _} -> false
      end

    name_salt_valid = byte_size(name_salt) == Naming.get_name_salt_byte_size()
    name_valid && name_salt_valid
  end

  @spec get_chain_state_name() :: Naming.chain_state_name()
  def get_chain_state_name(), do: :naming

  @doc """
  Changes the account state (balance) of the sender and receiver.
  """
  @spec process_chainstate!(
          NameClaimTx.t(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          block_height :: non_neg_integer(),
          ChainState.account(),
          tx_type_state()
        ) :: {ChainState.accounts(), tx_type_state()}
  def process_chainstate!(
        %NameClaimTx{} = tx,
        sender,
        fee,
        nonce,
        block_height,
        accounts,
        naming_state
      ) do
    sender_account_state = Account.get_account_state(accounts, sender)

    preprocess_check!(
      tx,
      sender_account_state,
      sender,
      fee,
      nonce,
      block_height,
      naming_state
    )

    new_senderount_state =
      sender_account_state
      |> deduct_fee(fee)
      |> Account.transaction_out_nonce_update(nonce)

    updated_accounts_chainstate = AccountStateTree.put(accounts, sender, new_senderount_state)

    pre_claim_commitment = Naming.create_commitment_hash(tx.name, tx.name_salt)
    claim_hash = NameUtil.normalized_namehash!(tx.name)
    claim = Naming.create_claim(claim_hash, tx.name, sender, block_height)

    updated_naming_chainstate =
      naming_state
      |> Map.delete(pre_claim_commitment)
      |> Map.put(claim_hash, claim)

    {updated_accounts_chainstate, updated_naming_chainstate}
  end

  @doc """
  Checks whether all the data is valid according to the NameClaimTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check!(
          NameClaimTx.t(),
          ChainState.account(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          block_height :: non_neg_integer(),
          tx_type_state()
        ) :: :ok | {:error, DataTx.reason()}
  def preprocess_check!(tx, account_state, sender, fee, nonce, _block_height, naming_state) do
    pre_claim_commitment = Naming.create_commitment_hash(tx.name, tx.name_salt)
    pre_claim = Map.get(naming_state, pre_claim_commitment)

    claim_hash = NameUtil.normalized_namehash!(tx.name)
    claim = Map.get(naming_state, claim_hash)

    cond do
      account_state.balance - fee < 0 ->
        throw({:error, "Negative balance"})

      account_state.nonce >= nonce ->
        throw({:error, "Nonce too small"})

      pre_claim == nil ->
        throw({:error, "Name has not been pre-claimed"})

      pre_claim.owner != sender ->
        throw({:error, "Sender is not pre-claim owner"})

      claim != nil ->
        throw({:error, "Name has aleady been claimed"})

      true ->
        :ok
    end
  end

  @spec deduct_fee(ChainState.account(), tx_type_state()) :: ChainState.account()
  def deduct_fee(account_state, fee) do
    new_balance = account_state.balance - fee
    Map.put(account_state, :balance, new_balance)
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(tx) do
    tx.data.fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end
end