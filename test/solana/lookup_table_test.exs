defmodule Solana.LookupTableTest do
  use ExUnit.Case, async: true

  import Solana.TestHelpers, only: [create_payer: 3]
  import Solana, only: [pubkey!: 1]

  alias Solana.{SystemProgram, LookupTable, RPC, Transaction}

  setup_all do
    {:ok, tracker} = RPC.Tracker.start_link(network: "localhost", t: 100)
    client = RPC.client(network: "localhost")
    {:ok, payer} = create_payer(tracker, client, commitment: "confirmed")

    [tracker: tracker, client: client, payer: payer]
  end

  describe "create_lookup_table/1" do
    test "can create an address lookup table", %{tracker: tracker, client: client, payer: payer} do
      new = Solana.keypair()

      tx_reqs = [
        RPC.Request.get_latest_blockhash(commitment: "confirmed"),
        RPC.Request.get_slot(commitment: "finalized")
      ]

      [{:ok, %{"blockhash" => blockhash}}, {:ok, slot}] = RPC.send(client, tx_reqs)

      {create_lookup_table_ix, lookup_table} = Solana.LookupTable.create_lookup_table(
        authority: pubkey!(new),
        payer: pubkey!(payer),
        recent_slot: slot
      )

      tx = %Transaction{
        instructions: [create_lookup_table_ix],
        signers: [payer],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, tx, commitment: "confirmed", timeout: 1_000)

      assert {:ok, %{}} =
        RPC.send(
          client,
          RPC.Request.get_account_info(lookup_table,
            commitment: "confirmed",
            encoding: "jsonParsed"
          )
        )
    end
  end

  describe "extend_lookup_table/1" do
    test "can extend an address lookup table", %{tracker: tracker, client: client, payer: payer} do
      new = Solana.keypair()

      tx_reqs = [
        RPC.Request.get_latest_blockhash(commitment: "confirmed"),
        RPC.Request.get_slot(commitment: "finalized")
      ]

      [{:ok, %{"blockhash" => blockhash}}, {:ok, slot}] = RPC.send(client, tx_reqs)

      {create_lookup_table_ix, lookup_table} = Solana.LookupTable.create_lookup_table(
        authority: pubkey!(new),
        payer: pubkey!(payer),
        recent_slot: slot
      )

      tx = %Transaction{
        instructions: [
          create_lookup_table_ix,
          LookupTable.extend_lookup_table(
            lookup_table: lookup_table,
            authority: pubkey!(new),
            payer: pubkey!(payer),
            new_keys: [SystemProgram.id()]
          )
        ],
        signers: [new, payer],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, tx, commitment: "confirmed", timeout: 1_000)

      {:ok, info} =
        RPC.send(
          client,
          RPC.Request.get_account_info(lookup_table,
            commitment: "confirmed",
            encoding: "jsonParsed"
          )
        )

      assert LookupTable.from_account_info(info).keys == [SystemProgram.id()]
    end
  end

  describe "feeze_lookup_table/1" do
    test "can freeze an address lookup table", %{tracker: tracker, client: client, payer: payer} do
      new = Solana.keypair()

      tx_reqs = [
        RPC.Request.get_latest_blockhash(commitment: "confirmed"),
        RPC.Request.get_slot(commitment: "finalized")
      ]

      [{:ok, %{"blockhash" => blockhash}}, {:ok, slot}] = RPC.send(client, tx_reqs)

      {create_lookup_table_ix, lookup_table} = Solana.LookupTable.create_lookup_table(
        authority: pubkey!(new),
        payer: pubkey!(payer),
        recent_slot: slot
      )

      tx = %Transaction{
        instructions: [
          create_lookup_table_ix,
          LookupTable.extend_lookup_table(
            lookup_table: lookup_table,
            authority: pubkey!(new),
            payer: pubkey!(payer),
            new_keys: [SystemProgram.id()]
          ),
          LookupTable.freeze_lookup_table(
            lookup_table: lookup_table,
            authority: pubkey!(new)
          )
        ],
        signers: [new, payer],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, tx, commitment: "confirmed", timeout: 1_000)

      {:ok, info} =
        RPC.send(
          client,
          RPC.Request.get_account_info(lookup_table,
            commitment: "confirmed",
            encoding: "jsonParsed"
          )
        )

      assert LookupTable.from_account_info(info).authority == nil
    end
  end

  describe "deactivate_lookup_table/1" do
    test "can deactivate an address lookup table", %{tracker: tracker, client: client, payer: payer} do
      new = Solana.keypair()

      tx_reqs = [
        RPC.Request.get_latest_blockhash(commitment: "confirmed"),
        RPC.Request.get_slot(commitment: "finalized")
      ]

      [{:ok, %{"blockhash" => blockhash}}, {:ok, slot}] = RPC.send(client, tx_reqs)

      {create_lookup_table_ix, lookup_table} = Solana.LookupTable.create_lookup_table(
        authority: pubkey!(new),
        payer: pubkey!(payer),
        recent_slot: slot
      )

      tx = %Transaction{
        instructions: [
          create_lookup_table_ix,
          LookupTable.extend_lookup_table(
            lookup_table: lookup_table,
            authority: pubkey!(new),
            payer: pubkey!(payer),
            new_keys: [SystemProgram.id()]
          ),
          LookupTable.deactivate_lookup_table(
            lookup_table: lookup_table,
            authority: pubkey!(new)
          )
        ],
        signers: [new, payer],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, tx, commitment: "confirmed", timeout: 1_000)

      {:ok, info} =
        RPC.send(
          client,
          RPC.Request.get_account_info(lookup_table,
            commitment: "confirmed",
            encoding: "jsonParsed"
          )
        )

      # When deactivated, the deactivation slot is set to the maximum unsigned 64-bit integer value
      assert LookupTable.from_account_info(info).deactivation_slot != (:math.pow(2, 64) |> trunc()) - 1
    end
  end
end
