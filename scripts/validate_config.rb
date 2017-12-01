require 'yaml'
require 'degiro'
require 'highline/import'

login  = ask('DeGiro login: ') { |q| q.echo = true }
passw  = ask('DeGiro passw: ') { |q| q.echo = false }
client = DeGiro::Client.new(login: login, password: passw)

ROOT_DIR = File.expand_path('..', File.dirname(__FILE__))
config = YAML.load(File.open("#{ROOT_DIR}/config.yml"))

config.each_key.each do |product_id|
  ticker_from_config = config[product_id][:ticker]
  ticker_from_degiro = client.find_product_by_id(id: product_id)[:ticker]

  if ticker_from_config == ticker_from_degiro
    puts "#{ticker_from_config} - #{ticker_from_degiro} - OK"
  else
    puts "#{ticker_from_config} - #{ticker_from_degiro} - PROBLEM"
  end
end
