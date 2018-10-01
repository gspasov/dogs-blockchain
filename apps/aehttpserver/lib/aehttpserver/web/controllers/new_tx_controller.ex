defmodule Aehttpserver.Web.NewTxController do
  use Aehttpserver.Web, :controller

  alias Aecore.Tx.SignedTx
  alias Aeutil.HTTPUtil
  alias Aecore.Tx.Pool.Worker, as: Pool

  def post_tx(conn, _params) do
    deserialized_tx = SignedTx.deserialize(conn.body_params)

    case Pool.add_transaction(deserialized_tx) do
      :error ->
        HTTPUtil.json_bad_request(conn, "Invalid transaction")

      :ok ->
        json(conn, "Successful operation")
    end
  end

  def post_tx(conn, _params) do
    signed_tx = SignedTx.create(data_tx, [signature])

    case Pool.add_transaction(signed_tx) do
      :error ->
        HTTPUtil.json_bad_request(conn, "Invalid transaction")

      :ok ->
        ## How are we going to know when the next block is mined
        ## And send such information to the caller connection?
        ## So that he knows in which block this transaction has been mined
        ## Maybe I can send the current block and say that possibly
        ## The transaction will be added with the next block
        ## Since this blockchain is going to be used solely for
        ## Dogs transactions
        json(conn, "Successful operation")
    end
  end

  def create_dogs_tx(conn, _params)
      when is_binary(hashed_data)
      and is_binary(sender)
      and byte_size(sender) == 32 do
    payload = %{
      receiver: <<0::32>>,
      amount: 0,
      version: SpendTx.get_tx_version,
      payload: hashed_data
    }

    fee = 0
    nonce = Account.nonce(Chain.chain_state().accounts, sender) + 1
    data_tx = DataTx.init(SpendTx, payload, sender, fee, nonce)
    encoded_tx = DataTx.rlp_encode(data_tx)
    
    json(conn, encoded_tx)
  end
end
