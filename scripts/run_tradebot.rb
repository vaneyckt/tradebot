require 'yaml'
require 'degiro'
require 'stock_quote'
require 'highline/import'

BUY_BUDGET = 1000.0
ROOT_DIR   = File.expand_path('..', File.dirname(__FILE__))
QUOTES_DIR = "#{ROOT_DIR}/quotes".freeze

def store_stock_quotes(config)
  config.each_key do |product_id|
    ticker   = config[product_id][:ticker]
    exchange = config[product_id][:exchange]
    quote    = StockQuote::Stock.quote("#{ticker}:#{exchange}").l.delete(',').to_f
    path     = "#{QUOTES_DIR}/#{Time.now.strftime('%Y-%m-%d')}-#{ticker}"
    File.open(path, 'a') { |f| f.puts(quote) }
  end
end

def create_sell_orders(client, config)
  portfolio    = client.get_portfolio
  transactions = client.get_transactions
  orders       = client.get_orders

  product_ids_enabled     = config.select { |_, cfg| cfg[:enabled] }.keys
  product_ids_owned       = portfolio.map { |prtfl| prtfl[:product_id] }
  product_ids_being_sold  = orders.select { |order| order[:type] == 'S' }.map { |order| order[:product_id] }
  product_ids_for_selling = (product_ids_owned & product_ids_enabled) - product_ids_being_sold

  product_ids_for_selling.each do |product_id|
    ticker         = config[product_id][:ticker]
    buy_price      = transactions.find { |tr| tr[:type] == 'B' && tr[:product_id] == product_id }[:price]
    portfolio_size = portfolio.find { |prtfl| prtfl[:product_id] == product_id }[:size]

    sell_size  = portfolio_size - config[product_id][:reserve_size]
    sell_price = (buy_price.to_f * config[product_id][:sell_constant]).round(2)

    if sell_size > 0
      puts "#{Time.now}: S - #{ticker} - #{sell_size} shares - $#{sell_price}"; $stdout.flush
      client.create_sell_order(product_id: product_id, size: sell_size, price: sell_price)
    end
  end
end

def create_buy_orders(client, config)
  orders = client.get_orders

  product_ids_enabled      = config.select { |_, cfg| cfg[:enabled] }.keys
  product_ids_being_sold   = orders.select { |order| order[:type] == 'S' }.map { |order| order[:product_id] }
  product_ids_being_bought = orders.select { |order| order[:type] == 'B' }.map { |order| order[:product_id] }
  product_ids_for_buying   = product_ids_enabled - product_ids_being_sold - product_ids_being_bought

  product_ids_for_buying.each do |product_id|
    ticker = config[product_id][:ticker]
    path   = "#{QUOTES_DIR}/#{Time.now.strftime('%Y-%m-%d')}-#{ticker}"
    quotes = File.readlines(path).map(&:to_f)

    buy_constant  = config[product_id][:buy_constant]
    min_cutoff    = config[product_id][:min_cutoff]
    max_cutoff    = config[product_id][:max_cutoff]
    current_quote = quotes.last

    if min_cutoff < current_quote && current_quote < max_cutoff
      if quotes.any? { |quote| min_cutoff < quote && quote < max_cutoff && current_quote <= (buy_constant * quote) }
        buy_size  = [(BUY_BUDGET / current_quote).to_i, 1].max
        buy_price = current_quote.round(2)

        if client.get_cash_funds['USD'] > (buy_size * buy_price)
          puts "#{Time.now}: B - #{ticker} - #{buy_size} shares - $#{buy_price}"; $stdout.flush
          client.create_buy_order(product_id: product_id, size: buy_size, price: buy_price)
        end
      end
    end
  end
end

login  = ask('DeGiro login: ') { |q| q.echo = true }
passw  = ask('DeGiro passw: ') { |q| q.echo = false }
client = DeGiro::Client.new(login: login, password: passw)
config = YAML.load(File.open("#{ROOT_DIR}/config.yml"))

loop do
  begin
    store_stock_quotes(config)
    create_sell_orders(client, config)
    create_buy_orders(client, config)
    puts "#{Time.now}: run successfully ended"
  rescue => e
    puts "#{Time.now}: an error occurred"
    puts "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
  ensure
    sleep 300
  end
end
