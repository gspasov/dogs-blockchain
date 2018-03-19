defmodule Aecore.Structures.Account do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  require Logger

  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.Account
  alias Aeutil.Bits
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SignedTx

  @type locked() :: list(%{amount: non_neg_integer(), block: non_neg_integer()})

  @type t :: %Account{
          balance: non_neg_integer(),
          nonce: non_neg_integer(),
          locked: locked()
        }

  @doc """
  Definition of Account structure

  ## Parameters
  - nonce: Out transaction count
  - balance: The acccount balance
  - locked: A list of maps holding the amount of tokens and block until which they are locked
  """
  defstruct [:balance, :nonce, :locked]
  use ExConstructor

  @spec empty() :: Account.t()
  def empty() do
    %Account{balance: 0, nonce: 0, locked: []}
  end

  @spec update_locked(Account.t(), integer()) :: Account.t()
  def update_locked(%{locked: locked} = account, new_height) do
    {unlocked_amount, updated_locked} =
      Enum.reduce(locked, {0, []}, fn %{amount: amount, block: locked_block} = elem,
                                      {updated_amount, updated_locked} ->
        cond do
          locked_block > new_height ->
            {updated_amount, updated_locked ++ [elem]}

          locked_block == new_height ->
            {updated_amount + amount, updated_locked}

          true ->
            Logger.error(fn -> "Update chain state locked: new block height (#{new_height})
              greater than lock time block (#{locked_block})" end)
            {updated_amount, updated_locked}
        end
      end)

    %Account{account | balance: account.balance + unlocked_amount, locked: updated_locked}
  end

  def base58_encode(bin) do
    Bits.encode58("ak$", bin)
  end

  @doc """
  Builds a SpendTx where the miners public key is used as a sender (from_acc)
  """
  @spec spend(Wallet.pubkey(), non_neg_integer(), non_neg_integer()) :: {:ok, SignedTx.t()}
  def spend(to_acc, amount, fee) do
    from_acc = Wallet.get_public_key()
    from_acc_priv_key = Wallet.get_private_key()
    nonce = Map.get(Chain.chain_state().accounts, from_acc, %{nonce: 0}).nonce + 1
    spend(from_acc, from_acc_priv_key, to_acc, amount, fee, nonce)
  end

  @doc """
  Build a SpendTx from the given sender keys to the receivers account
  """
  @spec spend(
          Wallet.pubkey(),
          Wallet.privkey(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, SignedTx.t()}
  def spend(from_acc, from_acc_priv_key, to_acc, amount, fee, nonce) do
    payload = %{to_acc: to_acc, value: amount, lock_time_block: 0}
    spend_tx = DataTx.init(SpendTx, payload, from_acc, fee, nonce)
    SignedTx.sign_tx(spend_tx, from_acc_priv_key)
  end

  @doc """
  Adds balance to a given address (public key)
  """
  @spec transaction_in(ChainState.account(), integer(), integer(), integer()) ::
          ChainState.account()
  def transaction_in(account_state, block_height, value, lock_time_block) do
    if block_height <= lock_time_block do
      new_locked = account_state.locked ++ [%{amount: value, block: lock_time_block}]
      Map.put(account_state, :locked, new_locked)
    else
      new_balance = account_state.balance + value
      Map.put(account_state, :balance, new_balance)
    end
  end

  @doc """
  Deducts balance from a given address (public key)
  """
  @spec transaction_out(ChainState.account(), integer(), integer(), integer(), integer()) ::
          ChainState.account()
  def transaction_out(account_state, block_height, value, nonce, lock_time_block) do
    account_state
    |> Map.put(:nonce, nonce)
    |> transaction_in(block_height, value, lock_time_block)
  end
end
