defmodule Explorer.SmartContract.ReaderTest do
  use ExUnit.Case, async: true
  use Explorer.DataCase

  doctest Explorer.SmartContract.Reader

  alias Explorer.SmartContract.Reader
  alias Plug.Conn
  alias Explorer.Chain.Hash

  @ethereum_jsonrpc_original Application.get_env(:ethereum_jsonrpc, :url)

  describe "query_contract/2" do
    setup do
      bypass = Bypass.open()

      Application.put_env(:ethereum_jsonrpc, :url, "http://localhost:#{bypass.port}")

      on_exit(fn ->
        Application.put_env(:ethereum_jsonrpc, :url, @ethereum_jsonrpc_original)
      end)

      {:ok, bypass: bypass}
    end

    test "correctly returns the result of a smart contract function", %{bypass: bypass} do
      blockchain_resp =
        "[{\"jsonrpc\":\"2.0\",\"result\":\"0x0000000000000000000000000000000000000000000000000000000000000000\",\"id\":\"get\"}]\n"

      Bypass.expect(bypass, fn conn -> Conn.resp(conn, 200, blockchain_resp) end)

      hash =
        :smart_contract
        |> insert()
        |> Map.get(:address_hash)
        |> Hash.to_string()

      assert Reader.query_contract(hash, [{"get", []}]) == %{"get" => [0]}
    end
  end

  describe "get_selectors/2" do
    test "return the selectors of the desired functions with their arguments" do
      abi = [
        %ABI.FunctionSelector{
          function: "fn1",
          returns: {:uint, 256},
          types: [uint: 256]
        },
        %ABI.FunctionSelector{
          function: "fn2",
          returns: {:uint, 256},
          types: [uint: 256]
        }
      ]

      fn1 = %ABI.FunctionSelector{
        function: "fn1",
        returns: {:uint, 256},
        types: [uint: 256]
      }

      assert Reader.get_selectors(abi, [{"fn1", [10]}]) == [{fn1, [10], "fn1"}]
    end
  end

  describe "get_selector_from_name/2" do
    test "return the selector of the desired function" do
      abi = [
        %ABI.FunctionSelector{
          function: "fn1",
          returns: {:uint, 256},
          types: [uint: 256]
        },
        %ABI.FunctionSelector{
          function: "fn2",
          returns: {:uint, 256},
          types: [uint: 256]
        }
      ]

      fn1 = %ABI.FunctionSelector{
        function: "fn1",
        returns: {:uint, 256},
        types: [uint: 256]
      }

      assert Reader.get_selector_from_name(abi, "fn1") == fn1
    end
  end

  describe "setup_call_payload/2" do
    test "returns the expected payload" do
      function_selector = %ABI.FunctionSelector{
        function: "get",
        returns: {:uint, 256},
        types: []
      }

      contract_address = "0x123789abc"
      id = "sum"

      assert Reader.setup_call_payload(
               {function_selector, [], id},
               contract_address
             ) == {"0x123789abc", "0x6d4ce63c", "sum"}
    end
  end

  describe "encode_function_call/2" do
    test "generates the correct encoding with no arguments" do
      function_selector = %ABI.FunctionSelector{
        function: "get",
        returns: {:uint, 256},
        types: []
      }

      assert Reader.encode_function_call(
               function_selector,
               []
             ) == "6d4ce63c"
    end

    test "generates the correct encoding with arguments" do
      function_selector = %ABI.FunctionSelector{
        function: "get",
        returns: {:uint, 256},
        types: [{:uint, 256}]
      }

      assert Reader.encode_function_call(
               function_selector,
               [10]
             ) == "9507d39a000000000000000000000000000000000000000000000000000000000000000a"
    end
  end

  describe "decode_results/2" do
    test "separates the selectors and map the results" do
      result =
        {:ok,
         [
           %{
             "id" => "get1",
             "jsonrpc" => "2.0",
             "result" => "0x000000000000000000000000000000000000000000000000000000000000002a"
           },
           %{
             "id" => "get2",
             "jsonrpc" => "2.0",
             "result" => "0x000000000000000000000000000000000000000000000000000000000000002a"
           },
           %{
             "id" => "get3",
             "jsonrpc" => "2.0",
             "result" => "0x0000000000000000000000000000000000000000000000000000000000000020"
           }
         ]}

      functions = [
        {%ABI.FunctionSelector{
           function: "get1",
           returns: {:uint, 256},
           types: [{:uint, 256}]
         }, [10], "get1"},
        {%ABI.FunctionSelector{
           function: "get2",
           returns: {:uint, 256},
           types: [{:uint, 256}]
         }, [10], "get2"},
        {%ABI.FunctionSelector{
           function: "get3",
           returns: {:uint, 256},
           types: [{:uint, 256}]
         }, [10], "get3"}
      ]

      assert Reader.decode_results(result, functions) == %{
               "get1" => [42],
               "get2" => [42],
               "get3" => [32]
             }
    end
  end

  describe "decode_result/1" do
    test "correclty decodes the blockchain result" do
      result = %{
        "id" => "0x7e50612682b8ee2a8bb94774d50d6c2955726526",
        "jsonrpc" => "2.0",
        "result" => "0x000000000000000000000000000000000000000000000000000000000000002a"
      }

      selector = %ABI.FunctionSelector{
        function: "get",
        returns: {:uint, 256},
        types: [{:uint, 256}]
      }

      expected_return = {"0x7e50612682b8ee2a8bb94774d50d6c2955726526", [42]}

      assert Reader.decode_result({result, selector}) == expected_return
    end
  end
end
