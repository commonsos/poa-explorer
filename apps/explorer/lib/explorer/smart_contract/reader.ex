defmodule Explorer.SmartContract.Reader do
  @moduledoc """
  Reads Smart Contract functions from the blockchain.

  For information on smart contract's Application Binary Interface (ABI), visit the
  [wiki](https://github.com/ethereum/wiki/wiki/Ethereum-Contract-ABI).
  """

  alias Explorer.Chain
  alias ABI.TypeDecoder

  @doc """
  Queries the contract functions on the blockchain and returns the call results.

  ## Examples

  Note that for this example to work the database must be up to date with the
  information available in the blockchain.

  Explorer.SmartContract.Reader.query_contract(
    "0x7e50612682b8ee2a8bb94774d50d6c2955726526",
    %{"sum" => [20, 22]}
  )
  # => %{"sum" => [42]}
  """
  @spec query_contract(String.t(), %{String.t() => [term()]}) :: map()
  def query_contract(contract_address_hash, functions) do
    functions =
      contract_address_hash
      |> Chain.find_smart_contract()
      |> Map.get(:abi)
      |> ABI.parse_specification()
      |> get_selectors(functions)

    functions
    |> Enum.map(&setup_call_payload(&1, contract_address_hash))
    |> EthereumJSONRPC.execute_contract_functions()
    |> decode_results(functions)
  end

  @doc """
  Given a list of function selectors from the ABI lib, and a list of functions names with their arguments, returns a list of selectors with their functions.
  """
  @spec get_selectors([%ABI.FunctionSelector{}], %{String.t() => [term()]}) :: [{%ABI.FunctionSelector{}, [term()]}]
  def get_selectors(abi, functions) do
    Enum.map(functions, fn {function_name, args} ->
      {get_selector_from_name(abi, function_name), args}
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
  @spec setup_call_payload({%ABI.FunctionSelector{}, [term()]}, String.t()) :: map()
  def setup_call_payload({function_selector, args}, contract_address_hash) do
    %{
      contract_address: contract_address_hash,
      data: "0x" <> encode_function_call(function_selector, args),
      id: function_selector.function
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
  @spec decode_results({any(), [map()]}, [{%ABI.FunctionSelector{}, [term()]}]) :: map()
  def decode_results({:ok, results}, functions) do
    selectors = Enum.map(functions, fn {selectors, _args} -> selectors end)

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
  @spec decode_result({map(), %ABI.FunctionSelector{}}) :: {String.t(), [String.t()]}
  def decode_result({%{"error" => %{"code" => code, "message" => message}, "id" => id}, _selector}) do
    {id, ["#{code} => #{message}"]}
  end

  def decode_result({%{"id" => id, "result" => result}, function_selector}) do
    {
      id,
      result
      |> String.slice(2..-1)
      |> Base.decode16!(case: :lower)
      |> TypeDecoder.decode_raw(List.wrap(function_selector.returns))
    }
  end

  @doc """
  List all the smart contract functions with its current value from the
  blockchain.

  Functions that require arguments can be queryable but won't list the current
  value at this moment.

  ## Examples

    $ Explorer.SmartContract.Reader.read_only_functions("0x798465571ae21a184a272f044f991ad1d5f87a3f")
    => [
      %{
        "constant" => true,
        "inputs" => [],
        "name" => "get",
        "outputs" => [%{"name" => "", "type" => "uint256", "value" => 0}],
        "payable" => false,
        "stateMutability" => "view",
        "type" => "function"
      },
      %{
        "constant" => true,
        "inputs" => [%{"name" => "x", "type" => "uint256"}],
        "name" => "with_arguments",
        "outputs" => [%{"name" => "", "type" => "bool", "value" => ""}],
        "payable" => false,
        "stateMutability" => "view",
        "type" => "function"
      }
    ]
  """
  @spec read_only_functions(String.t()) :: [%{}]
  def read_only_functions(contract_address_hash) do
    functions =
      contract_address_hash
      |> Chain.find_smart_contract()
      |> Map.get(:abi, [])
      |> Enum.filter(& &1["constant"])

    functions
    |> queryable_functions_current_value(contract_address_hash)
    |> Enum.concat(not_queryable_functions_current_value(functions))
  end

  defp not_queryable_functions_current_value(functions) do
    functions
    |> Enum.filter(&Enum.any?(&1["inputs"]))
    |> Enum.map(fn function ->
      values = link_outputs_and_values(%{}, Map.get(function, "outputs", []), function["name"])

      Map.replace!(function, "outputs", values)
    end)
  end

  defp queryable_functions_current_value(functions, contract_address_hash) do
    functions
    |> Enum.filter(&Enum.empty?(&1["inputs"]))
    |> Enum.map(fn function ->
      values =
        contract_address_hash
        |> fetch_from_blockchain(%{name: function["name"], args: function["inputs"], outputs: function["outputs"]})

      Map.replace!(function, "outputs", values)
    end)
  end

  @doc """
  Fetches the blockchain value of a function that requires arguments.
  """
  @spec query_function(String.t(), %{name: String.t(), args: nil}) :: [%{}]
  def query_function(contract_address_hash, %{name: name, args: nil}) do
    query_function(contract_address_hash, %{name: name, args: []})
  end

  @spec query_function(String.t(), %{name: String.t(), args: [term()]}) :: [%{}]
  def query_function(contract_address_hash, %{name: name, args: args}) do
    function =
      contract_address_hash
      |> Chain.find_smart_contract()
      |> Map.get(:abi, [])
      |> Enum.filter(fn function -> function["name"] == name end)
      |> List.first()

    contract_address_hash
    |> fetch_from_blockchain(%{name: name, args: args, outputs: function["outputs"]})
  end

  defp fetch_from_blockchain(contract_address_hash, %{name: name, args: args, outputs: outputs}) do
    contract_address_hash
    |> query_contract(%{name => args})
    |> link_outputs_and_values(outputs, name)
  end

  defp link_outputs_and_values(blockchain_values, outputs, function_name) do
    values = Map.get(blockchain_values, function_name, [""])

    for output <- outputs, value <- values do
      Map.put_new(output, "value", value)
    end
  end
end
