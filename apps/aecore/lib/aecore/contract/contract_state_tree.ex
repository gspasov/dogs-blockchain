defmodule ContractStateTree do

  @type contracts_state() :: Trie.t()

  @spec init_empty() :: contracts_state()
  def init_empty do
    PatriciaMerkleTree.new(:contracts)
  end

  def insert_contract(contract_tree, contract) do
    id = contract.id
    serialized = Serialization.rlp_encode(contract, :contract)

    new_contract_tree = PatriciaMerkleTree.insert(contract_tree, id.value, serialized)
    store_id = Contract.store_id(contract)
    new_contract_tree_with_storage =
      Enum.reduce(contract.store, contract_tree, fn {s_key, s_value}, tree_acc ->
        s_tree_key = <<store_id::binary, s_key::binary>>
        PatriciaMerkleTree.enter(tree_acc, s_tree_key, s_value)
      end)
  end

  def enter_contract(contract_tree, contract) do
    id = contract.id
    serialized = Serialization.rlp_encode(contract, :contract)

    updated_contract_tree = PatriciaMerkleTree.enter(contract_tree, id.value, contract)
    store_id = Contract.store_id(contract)
    old_contract_store = get_store(store_id, contract_tree)

    update_store(store_id, old_contract_store, contract.store, contract_tree)
  end

  def get_contract(contract_tree, key) do
    case PatriciaMerkleTree.lookup(contract_tree) do
      {:ok, serialized} ->
        {:ok, deserialized} = Serialization.rlp_decode(serialized)

        # TODO
      _ ->
        :none

    end
  end

  def update_store(store_id, old_store, new_store, tree) do
    merged_store = Map.merge(old_store, new_store)
    Enum.reduce(merged_store, tree, fn {s_key, s_value}, tree_acc ->
      insert_value =
        if Map.has_key?(new_store, s_key) do
          s_value
        else
          <<>>
        end

      s_tree_key = <<store_id::binary, s_key::binary>>
      PatriciaMerkleTree.enter(tree_acc, s_tree_key, insert_value)
    end)
  end

  def get_store(store_id, tree) do
    keys = PatriciaMerkleTree.all_keys(tree)
    Enum.reduce(keys, %{}, fn key, store_acc ->
      cond do
        byte_size(key) > 32 ->
          <<tree_store_id::size(264), s_key::binary>> = key
          if store_id == <<tree_store_id::binary>> do
            Map.put(store_acc, s_key, PatriciaMerkleTree.lookup(key))
          else
            store_acc
          end

        true ->
          store_acc
      end
    end)
  end

end
