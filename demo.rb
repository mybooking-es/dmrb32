require 'data_mapper'

# Load the environment variables wit
require 'dotenv'
Dotenv.load

#
# Define the model
#
class Demo
      include DataMapper::Resource
      storage_names[:default] = 'demos'
  property :id, Serial
  property :name, String, length: 255
  property :amount, Decimal, scale: 2, precision: 10, default: 0
end

#
# Define DataMapper
#
DataMapper.logger = DataMapper::Logger.new($stdout, :debug)
DataMapper.setup(:default, ENV['DB_URL'])
DataMapper::Model.raise_on_save_failure = true
DataMapper.finalize
DataMapper.auto_migrate!

# Create data
Demo.create(name: 'Test', amount: 10)
Demo.create(name: 'Test2', amount: 20)

# Retrieve an element
object = Demo.first

# Count elements
element_count = Demo.count

p "elementos: #{element_count}"
