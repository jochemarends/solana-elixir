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

      {create_lookup_table_ix, lookup_table} =
        LookupTable.create_lookup_table(
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

      {create_lookup_table_ix, lookup_table} =
        LookupTable.create_lookup_table(
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

  describe "freeze_lookup_table/1" do
    test "can freeze an address lookup table", %{tracker: tracker, client: client, payer: payer} do
      new = Solana.keypair()

      tx_reqs = [
        RPC.Request.get_latest_blockhash(commitment: "confirmed"),
        RPC.Request.get_slot(commitment: "finalized")
      ]

      [{:ok, %{"blockhash" => blockhash}}, {:ok, slot}] = RPC.send(client, tx_reqs)

      {create_lookup_table_ix, lookup_table} =
        LookupTable.create_lookup_table(
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
    test "can deactivate an address lookup table", %{
      tracker: tracker,
      client: client,
      payer: payer
    } do
      new = Solana.keypair()

      tx_reqs = [
        RPC.Request.get_minimum_balance_for_rent_exemption(LookupTable.byte_size(2),
          commitment: "confirmed"
        ),
        RPC.Request.get_latest_blockhash(commitment: "confirmed"),
        RPC.Request.get_slot(commitment: "finalized")
      ]

      [{:ok, lamports}, {:ok, %{"blockhash" => blockhash}}, {:ok, slot}] =
        RPC.send(client, tx_reqs)

      {create_lookup_table_ix, lookup_table} =
        LookupTable.create_lookup_table(
          authority: pubkey!(new),
          payer: pubkey!(payer),
          recent_slot: slot
        )

      tx = %Transaction{
        instructions: [
          create_lookup_table_ix,
          SystemProgram.transfer(
            lamports: lamports,
            from: pubkey!(payer),
            to: lookup_table
          ),
          LookupTable.extend_lookup_table(
            lookup_table: lookup_table,
            authority: pubkey!(new),
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

      %{deactivation_slot: deactivation_slot} = LookupTable.from_account_info(info)

      # When deactivated, the deactivation slot is set to the maximum unsigned
      # 64-bit integer value
      assert deactivation_slot != 2 ** 64 - 1
    end
  end

  describe "close_lookup_table/1" do
    # 5 Minutes
    @tag timeout: 5 * 60_000
    test "can close an address lookup table", %{tracker: tracker, client: client, payer: payer} do
      new = Solana.keypair()

      tx_reqs = [
        RPC.Request.get_minimum_balance_for_rent_exemption(LookupTable.byte_size(2),
          commitment: "confirmed"
        ),
        RPC.Request.get_latest_blockhash(commitment: "confirmed"),
        RPC.Request.get_slot(commitment: "finalized")
      ]

      [{:ok, lamports}, {:ok, %{"blockhash" => blockhash}}, {:ok, slot}] =
        RPC.send(client, tx_reqs)

      {create_lookup_table_ix, lookup_table} =
        LookupTable.create_lookup_table(
          authority: pubkey!(new),
          payer: pubkey!(payer),
          recent_slot: slot
        )

      tx = %Transaction{
        instructions: [
          create_lookup_table_ix,
          SystemProgram.transfer(
            lamports: lamports,
            from: pubkey!(payer),
            to: lookup_table
          ),
          LookupTable.extend_lookup_table(
            lookup_table: lookup_table,
            authority: pubkey!(new),
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

      %{deactivation_slot: deactivation_slot} = LookupTable.from_account_info(info)

      # When deactivated, the deactivation slot is set to the maximum unsigned
      # 64-bit integer value
      assert deactivation_slot != 2 ** 64 - 1

      # A lookup tables can only be closed once its deactivation slot is no
      # longer present in the SlotHashes sysvar
      recent_slots =
        Stream.repeatedly(fn ->
          Process.sleep(1_000)

          {:ok, %{"data" => %{"parsed" => %{"info" => info}}}} =
            RPC.send(
              client,
              RPC.Request.get_account_info(pubkey!("SysvarS1otHashes111111111111111111111111111"),
                commitment: "confirmed",
                encoding: "jsonParsed"
              )
            )

          Enum.map(info, & &1["slot"])
        end)

      Enum.find(recent_slots, &(deactivation_slot not in &1))

      {:ok, %{"blockhash" => blockhash}} =
        RPC.send(client, RPC.Request.get_latest_blockhash(commitment: "confirmed"))

      tx = %Transaction{
        instructions: [
          LookupTable.close_lookup_table(
            lookup_table: lookup_table,
            authority: pubkey!(new),
            recipient: pubkey!(new)
          )
        ],
        signers: [new, payer],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, tx, commitment: "confirmed", timeout: 1_000)
    end
  end
end
