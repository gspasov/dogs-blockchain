defmodule Aecore.Tx.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.DataTx
  alias Aecore.Tx.SignedTx
  alias Aeutil.Serialization
  alias Aecore.Chain.Chainstate
  alias Aecore.Account.Account
  alias Aecore.Keys
  alias Aeutil.Bits
  alias Aeutil.Hash

  require Logger

  @type t :: %SignedTx{
          data: DataTx.t(),
          signatures: list(Keys.pubkey())
        }

  @version 1

  defstruct [:data, :signatures]
  use ExConstructor
  use Aecore.Util.Serializable

  @spec create(DataTx.t(), list(Keys.pubkey())) :: SignedTx.t()
  def create(data, signatures \\ []) do
    %SignedTx{data: data, signatures: signatures}
  end

  def data_tx(%SignedTx{data: data}) do
    data
  end

  @spec validate(SignedTx.t()) :: :ok | {:error, String.t()}
  def validate(%SignedTx{data: data} = tx) do
    if signatures_valid?(tx) do
      DataTx.validate(data)
    else
      {:error, "#{__MODULE__}: Signatures invalid"}
    end
  end

  @spec validate(SignedTx.t(), non_neg_integer()) :: :ok | {:error, String.t()}
  def validate(%SignedTx{data: data} = tx, block_height) do
    if signatures_valid?(tx) do
      DataTx.validate(data, block_height)
    else
      {:error, "#{__MODULE__}: Signatures invalid"}
    end
  end

  @spec process_chainstate(Chainstate.t(), non_neg_integer(), SignedTx.t()) ::
          {:ok, Chainstate.t()} | {:error, String.t()}
  def process_chainstate(chainstate, block_height, %SignedTx{data: data}) do
    with :ok <- DataTx.preprocess_check(chainstate, block_height, data) do
      DataTx.process_chainstate(chainstate, block_height, data)
    else
      err ->
        err
    end
  end

  @doc """
  Takes the transaction that needs to be signed
  and the private key of the sender.
  Returns a signed tx

  ## Parameters
     - tx: The transaction data that it's going to be signed
     - priv_key: The priv key to sign with
  """
  @spec sign_tx(DataTx.t() | SignedTx.t(), binary()) ::
          {:ok, SignedTx.t()} | {:error, String.t()}
  def sign_tx(%DataTx{} = tx, priv_key) do
    sign_tx(%SignedTx{data: tx, signatures: []}, priv_key)
  end

  def sign_tx(%SignedTx{data: data, signatures: sigs}, priv_key) do
    new_signature =
      data
      |> DataTx.rlp_encode()
      |> Keys.sign(priv_key)

    #We need to make sure the sigs are sorted in order for the json/websocket api to function properly
    {:ok, %SignedTx{data: data, signatures: Enum.sort([new_signature | sigs])}}
  end

  def sign_tx(tx, _priv_key) do
    {:error, "#{__MODULE__}: Wrong Transaction data structure: #{inspect(tx)}"}
  end

  def get_sign_max_size do
    Application.get_env(:aecore, :signed_tx)[:sign_max_size]
  end

  @spec hash_tx(SignedTx.t() | DataTx.t()) :: binary()
  def hash_tx(%SignedTx{data: data}) do
    hash_tx(data)
  end

  def hash_tx(%DataTx{} = data) do
    Hash.hash(DataTx.rlp_encode(data))
  end

  @spec reward(DataTx.t(), Account.t()) :: Account.t()
  def reward(%DataTx{type: type, payload: payload}, account_state) do
    type.reward(payload, account_state)
  end

  def base58c_encode(bin) do
    Bits.encode58c("tx", bin)
  end

  def base58c_decode(<<"tx$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(bin) do
    {:error, "#{__MODULE__}: Wrong data: #{inspect(bin)}"}
  end

  def base58c_encode_root(bin) do
    Bits.encode58c("bx", bin)
  end

  def base58c_decode_root(<<"bx$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode_root(bin) do
    {:error, "#{__MODULE__}: Wrong data: #{inspect(bin)}"}
  end

  def base58c_encode_signature(bin) do
    if bin == nil do
      nil
    else
      Bits.encode58c("sg", bin)
    end
  end

  def base58c_decode_signature(<<"sg$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode_signature(_) do
    {:error, "#{__MODULE__}: Wrong data"}
  end

  @spec serialize(map()) :: map()
  def serialize(%SignedTx{} = tx) do
    signatures_length = length(tx.signatures)

    case signatures_length do
      0 ->
        %{"data" => DataTx.serialize(tx.data)}

      1 ->
        signature_serialized =
          tx.signatures
          |> Enum.at(0)
          |> Serialization.serialize_value(:signature)

        %{"data" => DataTx.serialize(tx.data), "signature" => signature_serialized}

      _ ->
        serialized_signatures =
          for signature <- tx.signatures do
            Serialization.serialize_value(signature, :signature)
          end

        %{
          "data" => DataTx.serialize(tx.data),
          "signatures" => serialized_signatures
        }
    end
  end

  @spec deserialize(map()) :: SignedTx.t()
  def deserialize(tx) do
    signed_tx = Serialization.deserialize_value(tx)
    data = DataTx.deserialize(signed_tx.data)

    cond do
      Map.has_key?(signed_tx, :signature) && signed_tx.signature != nil ->
        create(data, [signed_tx.signature])

      Map.has_key?(signed_tx, :signatures) && signed_tx.signatures != nil ->
        create(data, signed_tx.signatures)

      true ->
        create(data, [])
    end
  end

  def signatures_valid?(%SignedTx{data: data, signatures: sigs}) do
    senders = DataTx.senders(data)
    if length(sigs) != length(senders) do
      Logger.error("Wrong signature count")
      false
    else
      data_binary = DataTx.rlp_encode(data)
      many_signatures_check(sigs, data_binary, senders)
    end
  end

  def signature_valid_for?(%SignedTx{data: data, signatures: signatures}, pubkey) do
    data_binary = DataTx.rlp_encode(data)
    if pubkey not in DataTx.senders(data) do
      false
    else
      case single_signature_check(signatures, data_binary, pubkey) do
        {:ok, _} ->
          true
        :error ->
          false
      end
    end
  end

  defp many_signatures_check(signatures, data_binary, [pubkey | remaining_pubkeys]) do
    case single_signature_check(signatures, data_binary, pubkey) do
      {:ok, remaining_signatures} ->
        many_signatures_check(remaining_signatures, data_binary, remaining_pubkeys)
      :error ->
        false
    end
  end

  defp many_signatures_check([], _data_binary, []) do
    true
  end

  defp many_signatures_check(_, _, _) do
    false
  end

  defp single_signature_check(signatures, data_binary, pubkey) do
    if Keys.key_size_valid?(pubkey) do
      internal_single_signature_check(signatures, data_binary, pubkey)
    else
      Logger.error("Wrong pubkey size #{inspect(pubkey)}")
      :error
    end
  end

  defp internal_single_signature_check([signature | rest_signatures], data_binary, pubkey) do
    if Keys.verify(data_binary, signature, pubkey) do
      {:ok, rest_signatures}
    else
      case internal_single_signature_check(rest_signatures, data_binary, pubkey) do
        {:ok, unchecked_sigs} ->
          {:ok, [signature | unchecked_sigs]}
        :error ->
          :error
      end
    end
  end

  defp internal_single_signature_check([], _data_binary, pubkey) do
    Logger.error("Signature of #{inspect(pubkey)} invalid")
    :error
  end

  def encode_to_list(%SignedTx{} = tx) do
    [
      :binary.encode_unsigned(@version),
      Enum.sort(tx.signatures),
      DataTx.rlp_encode(tx.data)
    ]
  end

  def decode_from_list(@version, [signatures, data]) do
    case DataTx.rlp_decode(data) do
      {:ok, data} ->
        #make sure that the sigs are sorted - we cannot trust user input ;)
        {:ok, %SignedTx{data: data, signatures: Enum.sort(signatures)}}

      {:error, _} = error ->
        error
    end
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
