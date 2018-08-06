defmodule ContractCallStateTree do
  alias Aeutil.PatriciaMerkleTree
  alias Aeutil.Serialization
  alias Aecore.Chain.Identifier
  alias MerklePatriciaTree.Trie

  @type calls_state() :: Trie.t()

  @spec init_empty() :: calls_state()

  def init_empty do
    PatriciaMerkleTree.new(:calls)
  end

  def prune() do
    # TODO
  end

  @spec insert_call(calls_state(), map()) :: calls_state()
  def insert_call(call_tree, call) do
    contract_id = call.contract_address
    call_id = Call.id(call)
    call_tree_id = construct_call_tree_id(contract_id, call_id)

    serialized = Serialization.rlp_encode(call, :call)
    new_call_tree = PatriciaMerkleTree.insert(call_tree, call_tree_id, serialized)
  end

  @spec get_call(calls_state(), map()) :: calls_state()
  def get_call(calls_tree, key) do
    case PatriciaMerkleTree.lookup(calls_tree, key) do
      {:ok, value} ->
        {:ok, deserialized_call} = Serialization.rlp_decode(value)

        identified_call =
          case deserialized_call do
            %{
              :caller_address => caller,
              :caller_nonce => _nonce,
              :height => _block_height,
              :contract_address => address,
              :gas_price => _gas_price,
              :gas_used => _gas_used,
              :return_value => _return_value,
              :return_type => _return_type
            } ->
              {:ok, identified_caller_address} = Identifier.create_identity(caller, :contract)
              {:ok, identified_contract_address} = Identifier.create_identity(address, :contract)

              %{
                deserialized_call
                | caller_address: identified_caller_address,
                  contract_address: identified_contract_address
              }
          end

      _ ->
        :none
    end
  end

  defp construct_call_tree_id(contract_id, call_id) do
    <<contract_id.value::binary, call_id::binary>>
  end
end
