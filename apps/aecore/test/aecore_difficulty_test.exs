defmodule DifficultyTest do

  use ExUnit.Case

  doctest Aecore.Utils.Blockchain.Difficulty

  alias Aecore.Utils.Blockchain.Difficulty, as: Difficulty
  alias Aecore.Structures.Block, as: Block
  alias Aecore.Structures.Header, as:  Header
  alias Aecore.Block.Genesis, as: Genesis

  test "difficulty calculation genesis block only" do
    blocks = [
      Genesis.genesis_block
    ]

    assert 1 == Difficulty.calculate_next_difficulty(blocks)
  end

  test "difficulty calculation" do
    blocks = [
      %Block{header: %Header{difficulty_target: 6,
        height: 1, nonce: 0, prev_hash: <<1, 24, 45>>, timestamp: 130000,
        txs_hash: "\f{\f", version: 1}, txs: []},
      %Block{header: %Header{difficulty_target: 1,
        height: 1, nonce: 0, prev_hash: <<1, 24, 45>>, timestamp: 20000,
        txs_hash: "\f{\f", version: 1}, txs: []},
      %Block{header: %Header{difficulty_target: 1,
        height: 0, nonce: 0,
        prev_hash: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>, timestamp: 10000,
        txs_hash: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>, version: 1}, txs: []}
    ]

    assert 6 == Difficulty.calculate_next_difficulty(blocks)
  end

  test "max difficulty change" do
    assert 4 == Difficulty.limit_max_difficulty_change(10, 2)
    assert 10 == Difficulty.limit_max_difficulty_change(10, 9)
    assert 8 == Difficulty.limit_max_difficulty_change(8, 9)
    assert 10 == Difficulty.limit_max_difficulty_change(8, 12)
  end
end
