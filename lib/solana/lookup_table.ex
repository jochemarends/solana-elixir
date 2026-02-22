defmodule Solana.LookupTable do
  @moduledoc """
  Functions for interacting with Solana's
  [Address Lookup Table]
  (https://solana.com/developers/guides/advanced/lookup-tables) Program.
  """
  alias Solana.{Account, Instruction, Key, SystemProgram}
  import Solana.Helpers

  @typedoc "Address lookup table account metadata."
  @type t :: %__MODULE__{
          authority: Key.t() | nil,
          keys: [Key.t()],
          deactivation_slot: non_neg_integer(),
          last_extended_slot: non_neg_integer(),
          last_extended_slot_start_index: non_neg_integer()
        }

  defstruct [
    :authority,
    :keys,
    :deactivation_slot,
    :last_extended_slot,
    :last_extended_slot_start_index
  ]

  @doc """
  The on-chain size of an address lookup table containing the given number of keys.
  """
  def byte_size(key_count \\ 0), do: 56 + key_count * 32

  @doc """
  The Address Lookup Table Program's program ID.
  """
  def id(), do: Solana.pubkey!("AddressLookupTab1e1111111111111111111111111")

  @doc """
  Finds the address lookup table account addresss associated with a given
  authority and recent block's slot.
  """
  def find_address(authority, recent_slot) do
    Solana.Key.find_address([authority, <<recent_slot::little-64>>], id())
  end

  @doc """
  Translates the result of a `Solana.RPC.Request.get_account_info/2` into a
  `t:Solana.LookupTable.t/0`.
  """
  @spec from_account_info(info :: map) :: t() | :error
  def from_account_info(%{"data" => %{"parsed" => %{"info" => info}}}) do
    from_lookup_table_account_info(info)
  end

  def from_account_info(_), do: :error

  defp from_lookup_table_account_info(%{"authority" => authority} = info) do
    from_lookup_table_account_info(info, Solana.pubkey!(authority))
  end

  defp from_lookup_table_account_info(info), do: from_lookup_table_account_info(info, nil)

  defp from_lookup_table_account_info(
         %{
           "addresses" => keys,
           "deactivationSlot" => deactivation_slot,
           "lastExtendedSlot" => last_extended_slot,
           "lastExtendedSlotStartIndex" => last_extended_slot_start_index
         },
         authority
       ) do
    %__MODULE__{
      authority: authority,
      keys: Enum.map(keys, &Solana.pubkey!/1),
      deactivation_slot: String.to_integer(deactivation_slot),
      last_extended_slot: String.to_integer(last_extended_slot),
      last_extended_slot_start_index: last_extended_slot_start_index
    }
  end

  @create_lookup_table_schema [
    authority: [
      type: {:custom, Solana.Key, :check, []},
      required: true,
      doc: "Public key of the account used to derive and control the address lookup table"
    ],
    payer: [
      type: {:custom, Solana.Key, :check, []},
      required: true,
      doc: "Public key of the account that will fund the created address lookup table"
    ],
    payer: [
      type: {:custom, Solana.Key, :check, []},
      required: true,
      doc: "Account that will fund the created address lookup table"
    ],
    recent_slot: [
      type: :non_neg_integer,
      required: true,
      doc: "A recent slot must be used in the derivation path for each initialized table"
    ],
    authority_should_sign?: [
      type: :boolean,
      default: false,
      doc:
        "Whether the authority should be a signer, which was required before version 1.1 of the address lookup table program"
    ]
  ]
  @doc """
  Generates the instructions for creating a new address lookup table.

  Returns a tuple containing the instructions and the public key of the derived
  address lookup table account.

  ## Options

  #{NimbleOptions.docs(@create_lookup_table_schema)}
  """
  def create_lookup_table(opts) do
    with {:ok, params} <- validate(opts, @create_lookup_table_schema) do
      create_lookup_table_ix(params)
    end
  end

  defp create_lookup_table_ix(params) do
    with {:ok, lookup_table, bump_seed} <-
           find_address(params.authority, params.recent_slot) do
      ix = %Instruction{
        program: id(),
        accounts: [
          %Account{key: lookup_table, signer?: false, writable?: true},
          %Account{
            key: params.authority,
            signer?: params.authority_should_sign?,
            writable?: false
          },
          %Account{key: params.payer, signer?: true, writable?: true},
          %Account{key: SystemProgram.id(), signer?: false, writable?: false}
        ],
        data:
          Instruction.encode_data([
            {0, 32},
            {params.recent_slot, 64},
            {bump_seed, 8}
          ])
      }

      {ix, lookup_table}
    end
  end

  @freeze_lookup_table_schema [
    lookup_table: [
      type: {:custom, Solana.Key, :check, []},
      required: true,
      doc: "Public key of the address lookup table"
    ],
    authority: [
      type: {:custom, Solana.Key, :check, []},
      required: true,
      doc: "Public key of the account used to derive and control the address lookup table"
    ]
  ]
  @doc """
  Generates the instructions for freezing an address lookup table.

  Freezing an addess lookup table makes it immutable. It can never be closed or
  extended again. Only non-empty lookup tables can be frozen.

  ## Options

  #{NimbleOptions.docs(@freeze_lookup_table_schema)}
  """
  def freeze_lookup_table(opts) do
    with {:ok, params} <- validate(opts, @freeze_lookup_table_schema) do
      freeze_lookup_table_ix(params)
    end
  end

  defp freeze_lookup_table_ix(params) do
    %Instruction{
      program: id(),
      accounts: [
        %Account{key: params.lookup_table, signer?: false, writable?: true},
        %Account{key: params.authority, signer?: true, writable?: false}
      ],
      data: Instruction.encode_data([{1, 32}])
    }
  end

  @extend_lookup_table_schema [
    lookup_table: [
      type: {:custom, Solana.Key, :check, []},
      required: true,
      doc: "Public key of the address lookup table"
    ],
    authority: [
      type: {:custom, Solana.Key, :check, []},
      required: true,
      doc: "Public key of the account used to derive and control the address lookup table"
    ],
    payer: [
      type: {:custom, Solana.Key, :check, []},
      required: false,
      doc: "Public key of the account that will fund any fees needed to extend the lookup table"
    ],
    new_keys: [
      type: {:list, {:custom, Solana.Key, :check, []}},
      required: true,
      doc: "Pubic keys of the accounts that will be added to the address lookup table"
    ]
  ]
  @doc """
  Generates the instructions for extending an address lookup table.

  ## Options

  #{NimbleOptions.docs(@extend_lookup_table_schema)}
  """
  def extend_lookup_table(opts) do
    with {:ok, params} <- validate(opts, @extend_lookup_table_schema) do
      extend_lookup_table_ix(params)
    end
  end

  defp extend_lookup_table_ix(params) do
    %Instruction{
      program: id(),
      accounts: [
        %Account{key: params.lookup_table, signer?: false, writable?: true},
        %Account{key: params.authority, signer?: true, writable?: false}
        | payer_keys(params)
      ],
      data:
        Instruction.encode_data([
          {2, 32},
          {length(params.new_keys), 64}
          | params.new_keys
        ])
    }
  end

  defp payer_keys(%{payer: nil}), do: []

  defp payer_keys(%{payer: payer}) do
    [
      %Account{key: payer, signer?: true, writable?: true},
      %Account{key: SystemProgram.id(), signer?: false, writable?: false}
    ]
  end

  defp payer_keys(_), do: []

  @deactivate_lookup_table_schema [
    lookup_table: [
      type: {:custom, Solana.Key, :check, []},
      required: true,
      doc: "Public key of the address lookup table"
    ],
    authority: [
      type: {:custom, Solana.Key, :check, []},
      required: true,
      doc: "Public key of the account used to derive and control the address lookup table"
    ]
  ]
  @doc """
  Generates the instructions for deactivating an address lookup table.

  Once deactivated, an address lookup table can no longer be extended or used
  for lookups in transactions. A lookup tables can only be closed once its
  deactivation slot is no longer present in the
  [SlotHashes](https://docs.anza.xyz/runtime/sysvars/#slothashes) sysvar.

  ## Options

  #{NimbleOptions.docs(@deactivate_lookup_table_schema)}
  """
  def deactivate_lookup_table(opts) do
    with {:ok, params} <- validate(opts, @deactivate_lookup_table_schema) do
      deactivate_lookup_table_ix(params)
    end
  end

  defp deactivate_lookup_table_ix(params) do
    %Instruction{
      program: id(),
      accounts: [
        %Account{key: params.lookup_table, signer?: false, writable?: true},
        %Account{key: params.authority, signer?: true, writable?: false}
      ],
      data: Instruction.encode_data([{3, 32}])
    }
  end

  @close_lookup_table_schema [
    lookup_table: [
      type: {:custom, Solana.Key, :check, []},
      required: true,
      doc: "Public key of the address lookup table"
    ],
    authority: [
      type: {:custom, Solana.Key, :check, []},
      required: true,
      doc: "Public key of the account used to derive and control the address lookup table"
    ],
    recipient: [
      type: {:custom, Solana.Key, :check, []},
      required: true,
      doc: "Public key of the account to send the closed account's lamports to"
    ]
  ]
  @doc """
  Generates the instructions for closing an address lookup table.

  ## Options

  #{NimbleOptions.docs(@close_lookup_table_schema)}
  """
  def close_lookup_table(opts) do
    with {:ok, params} <- validate(opts, @close_lookup_table_schema) do
      close_lookup_table_ix(params)
    end
  end

  defp close_lookup_table_ix(params) do
    %Instruction{
      program: id(),
      accounts: [
        %Account{key: params.lookup_table, signer?: false, writable?: true},
        %Account{key: params.authority, signer?: true, writable?: true},
        %Account{key: params.recipient, signer?: false, writable?: true}
      ],
      data: Instruction.encode_data([{4, 32}])
    }
  end
end
