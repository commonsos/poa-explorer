defmodule Explorer.SmartContract.Reader do
  @moduledoc """
  Reads Smart Contract functions from the blockchain.

  For information on smart contract's Application Binary Interface (ABI), visit the
  [wiki](https://github.com/ethereum/wiki/wiki/Ethereum-Contract-ABI).
  """

  alias Explorer.Chain
  alias ABI.TypeDecoder

  @doc """
  Queries a contract function on the blockchain and returns the call result.

  ## Examples

  Note that for this example to work the database must be up to date with the
  information available in the blockchain.

  Explorer.SmartContract.Reader.query_contract(
    "0x7e50612682b8ee2a8bb94774d50d6c2955726526",
    [{"sum", [20, 22]}]
  )
  # => %{"sum" => [42]}
  """
  @spec query_contract(String.t(), [{String.t(), [term()]}]) :: map()
  def query_contract(contract_address_hash, functions_to_execute) do
    functions_to_execute =
      contract_address_hash
      |> Chain.find_smart_contract()
      |> Map.get(:abi)
      |> ABI.parse_specification()
      |> get_selectors(functions_to_execute)

    functions_to_execute
    |> Enum.map(&setup_call_payload(&1, contract_address_hash))
    |> EthereumJSONRPC.execute_contract_functions()
    |> decode_results(functions_to_execute)
  end

  @doc """
  Given a list of function selectors from the ABI lib, and a list of functions names with their arguments, returns a list of selectors with their functions.
  """
  @spec get_selectors([%ABI.FunctionSelector{}], [{String.t(), [term()]}]) :: [{%ABI.FunctionSelector{}, [term()]}]
  def get_selectors(abi, functions) do
    Enum.map(functions, fn {function_name, args} ->
      {get_selector_from_name(abi, function_name), args, function_name}
    end)
  end

  @doc """
  Given a list of function selectors from the ABI lib, and a function name, get the selector for that function.
  """
  @spec get_selector_from_name([%ABI.FunctionSelector{}], String.t()) :: %ABI.FunctionSelector{}
  def get_selector_from_name(abi, function_name) do
    Enum.find(abi, fn selector -> function_name == selector.function end)
  end

  @doc """
  Given a function selector, a contract address hash and a (possibly empty) list of arguments, returns what EthereumJSONRPC expects.
  """
  @spec setup_call_payload({%ABI.FunctionSelector{}, [term()], String.t()}, String.t()) ::
          {String.t(), String.t(), String.t()}
  def setup_call_payload({function_selector, args, id}, contract_address_hash) do
    {
      contract_address_hash,
      "0x" <> encode_function_call(function_selector, args),
      id
    }
  end

  @doc """
  Given a function selector and a list of arguments, returns their econded versions.

  This is what is expected on the Json RPC data parameter.
  """
  @spec encode_function_call(%ABI.FunctionSelector{}, [term()]) :: String.t()
  def encode_function_call(function_selector, args) do
    function_selector
    |> ABI.encode(args)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Given the result set from the blockchain, and the functions selectors, returns the results decoded.
  """
  def decode_results({:ok, results}, functions) do
    selectors = Enum.map(functions, fn {selectors, _args, _id} -> selectors end)

    results
    |> Enum.map(&join_result_and_selector(&1, selectors))
    |> Enum.map(&decode_result/1)
    |> Map.new()
  end

  defp join_result_and_selector(result, selectors) do
    {result, Enum.find(selectors, &(&1.function == result["id"]))}
  end

  @doc """
  Given a result from the blockchain, and the function selector, returns the result decoded.
  """
  def decode_result({result, function_selector}) do
    {
      result["id"],
      result
      |> Map.get("result")
      |> String.slice(2..-1)
      |> Base.decode16!(case: :lower)
      |> TypeDecoder.decode_raw(List.wrap(function_selector.returns))
    }
  end
end
