defmodule ExplorerWeb.TransactionInternalTransactionController do
  use ExplorerWeb, :controller

  import ExplorerWeb.Chain, only: [paging_options: 1, next_page_params: 2, split_list_by_page: 1]

  alias Explorer.{Chain, Market}
  alias Explorer.ExchangeRates.Token

  def index(conn, %{"transaction_id" => hash_string} = params) do
    with {:ok, hash} <- Chain.string_to_transaction_hash(hash_string),
         {:ok, transaction} <-
           Chain.hash_to_transaction(
             hash,
             necessity_by_association: %{
               block: :optional,
               from_address: :optional,
               to_address: :optional
             }
           ) do
      full_options =
        Keyword.merge(
          [
            necessity_by_association: %{
              from_address: :required,
              to_address: :optional
            }
          ],
          paging_options(params)
        )

      internal_transactions_plus_one = Chain.transaction_to_internal_transactions(transaction, full_options)

      {internal_transactions, next_page} = split_list_by_page(internal_transactions_plus_one)

      max_block_number = max_block_number()

      render(
        conn,
        "index.html",
        exchange_rate: Market.get_exchange_rate(Explorer.coin()) || Token.null(),
        internal_transactions: internal_transactions,
        max_block_number: max_block_number,
        next_page_params: next_page_params(next_page, internal_transactions),
        transaction: transaction
      )
    else
      :error ->
        not_found(conn)

      {:error, :not_found} ->
        not_found(conn)
    end
  end

  defp max_block_number do
    case Chain.max_block_number() do
      {:ok, number} -> number
      {:error, :not_found} -> 0
    end
  end
end
