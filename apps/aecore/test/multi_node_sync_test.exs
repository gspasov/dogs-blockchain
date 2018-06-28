defmodule MultiNodeSyncTest do

  use ExUnit.Case
  alias Aecore.MultiNodeTestFramework.Worker, as: TestFramework

  setup do
    TestFramework.start_link %{}

    on_exit(fn ->
      :ok
    end)
  end

  @tag :sync_test
  test "test nodes sync" do
    TestFramework.new_node("node1", 4001)
    TestFramework.new_node("node2", 4002)
    TestFramework.new_node("node3", 4003)

    :timer.sleep(2000)
    TestFramework.sync_two_nodes "node1", "node2"
    TestFramework.sync_two_nodes "node2", "node3"

    TestFramework.mine_sync_block "node1"
    TestFramework.spend_tx "node1"
    TestFramework.mine_sync_block "node1"
    result = TestFramework.compare_nodes "node1", "node2"
    assert result == :synced
  end
end
