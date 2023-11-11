module DataMapper
  module Chainable

    def self.extended(base)
      @@base = base
      p "Chainable-extended:: #{@@base.inspect}"
    end

    # @api private
    def chainable(&block)
      p "AQUI!!"
      p "Chainable-chainable:: #{@@base.inspect}"
      mod = Module.new(&block)
      #@@base.include mod
      #@@base.send(:include, mod)
      @@base.send(:prepend, mod)
      #@@base.prepend mod
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
