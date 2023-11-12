module DataMapper
  module Chainable

    def self.extended(base)
      p "Chainable-extended:: #{base.inspect}"
    end

    # @api private
    def chainable(&block)
      mod = Module.new(&block)
      include mod
      mod
    end

    # @api private
    def extendable(&block)
      mod = Module.new(&block)
      extend mod
      mod
    end
  end # module Chainable
end # module DataMapper
