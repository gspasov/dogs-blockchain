defmodule Contract do

  @store_prefix 16

  @type contract :: %{
    id: Identifier.t(),
    owner: Identifier.t(),
    vm_version: byte(),
    code: binary(),
    store: %{binary() => binary()},
    log: binary(),
    active: boolean(),
    referers: [Identifier.t()],
    deposit: non_neg_integer()
  }

  @type t :: contract()

  def rlp_encode(tag, version, contract) do
    {:ok, encoded_id} = Identifier.encode_data(contract.id)
    {:ok, encoded_owner} = Identifier.encode_data(contract.owner)

    active = case contract.active do
      true -> 1
      false -> 0
    end

    encoded_referers =
      Enum.reduce(contract.referers, [], fn referer, acc ->
        {:ok, encoded_referer} = Identifier.encode_data(contract.id)
        [encoded_referer | acc]
      end)
      |> Enum.reverse()

    [
      tag,
      version,
      encoded_id,
      encoded_owner,
      contract.vm_version,
      contract.code,
      Serialization.transform_item(contract.store),
      contract.log,
      active,
      encoded_referers,
      contract.deposit
    ]
  end

  def store_id(contract) do
    id = contract.id
    {:ok, decoded_id} = Identifier.decode_data(id)

    <<decoded_id::binary, @store_prefix>>
  end

end
