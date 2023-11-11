module DataMapper
  module Chainable

    def self.extended(base)
      @@base = base
      p "Chainable-extended:: #{@@base.inspect}"
    end

=begin
    # @api private THIS WORKS
    def chainable(&block)

      mod = Module.new
      mod.instance_variable_set(:@original_included, included_modules)
      mod.define_singleton_method(:included) do |base|
        @original_included.each do |oi|
          if oi.respond_to?(:included)
            oi.included(base)
          end
        end
        base.class_eval(&block)
      end

      include mod
    end
=end

    # @api private
    def chainable(&block)

    #  p "base:: #{@@base.inspect}"

    #  p "do chainable"

    #  p "modules-before:: #{included_modules.inspect}"

      mod = Module.new(&block)
      include mod

    #  p "modules-after:: #{included_modules.inspect}"

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
