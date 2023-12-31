require 'dm-core'

module DataMapper
  class Transaction
    extend Chainable

    # @api private
    attr_accessor :state

    # @api private
    def none?
      state == :none
    end

    # @api private
    def begin?
      state == :begin
    end

    # @api private
    def rollback?
      state == :rollback
    end

    # @api private
    def commit?
      state == :commit
    end

    # Create a new Transaction
    #
    # @see Transaction#link
    #
    # In fact, it just calls #link with the given arguments at the end of the
    # constructor.
    #
    # @api public
    def initialize(*things)
      @transaction_primitives = {}
      self.state = :none
      @adapters = {}
      link(*things)
      if block_given?
        warn "Passing block to #{self.class.name}.new is deprecated (#{caller[0]})"
        commit { |*block_args| yield(*block_args) }
      end
    end

    # Associate this Transaction with some things.
    #
    # @param [Object] things
    #   the things you want this Transaction associated with:
    #
    #   Adapters::AbstractAdapter subclasses will be added as
    #     adapters as is.
    #   Arrays will have their elements added.
    #   Repository will have it's own @adapters added.
    #   Resource subclasses will have all the repositories of all
    #     their properties added.
    #   Resource instances will have all repositories of all their
    #     properties added.
    #
    # @param [Proc] block
    #   a block (taking one argument, the Transaction) to execute within
    #   this transaction. The transaction will begin and commit around
    #   the block, and rollback if an exception is raised.
    #
    # @api private
    def link(*things)
      unless none?
        raise "Illegal state for link: #{state}"
      end

      things.each do |thing|
        case thing
          when DataMapper::Adapters::AbstractAdapter
            @adapters[thing] = :none if thing.respond_to?(:transaction_primitive)
          when DataMapper::Repository
            link(thing.adapter)
          when DataMapper::Model
            link(*thing.repositories)
          when DataMapper::Resource
            link(thing.model)
          when Array
            link(*thing)
          else
            raise "Unknown argument to #{self.class}#link: #{thing.inspect} (#{thing.class})"
        end
      end

      if block_given?
        commit { |*block_args| yield(*block_args) }
      else
        self
      end
    end

    # Begin the transaction
    #
    # Before #begin is called, the transaction is not valid and can not be used.
    #
    # @api private
    def begin
      unless none?
        raise "Illegal state for begin: #{state}"
      end

      each_adapter(:connect_adapter, [:log_fatal_transaction_breakage])
      each_adapter(:begin_adapter, [:rollback_and_close_adapter_if_begin, :close_adapter_if_none])
      self.state = :begin
    end

    # Commit the transaction
    #
    #   If no block is given, it will simply commit any changes made since the
    #   Transaction did #begin.
    #
    # @param block<Block>   a block (taking the one argument, the Transaction) to
    #   execute within this transaction. The transaction will begin and commit
    #   around the block, and roll back if an exception is raised.
    #
    # @api private
    def commit
      if block_given?
        unless none?
          raise "Illegal state for commit with block: #{state}"
        end

        begin
          self.begin
          rval = within { |*block_args| yield(*block_args) }
        rescue Exception => exception
          if begin?
            rollback
          end
          raise exception
        else
          if begin?
            commit
          end
          return rval
        end
      else
        unless begin?
          raise "Illegal state for commit without block: #{state}"
        end
        each_adapter(:commit_adapter, [:log_fatal_transaction_breakage])
        each_adapter(:close_adapter, [:log_fatal_transaction_breakage])
        self.state = :commit
      end
    end

    # Rollback the transaction
    #
    # Will undo all changes made during the transaction.
    #
    # @api private
    def rollback
      unless begin?
        raise "Illegal state for rollback: #{state}"
      end
      each_adapter(:rollback_adapter_if_begin, [:rollback_and_close_adapter_if_begin, :close_adapter_if_none])
      each_adapter(:close_adapter_if_open, [:log_fatal_transaction_breakage])
      self.state = :rollback
    end

    # Execute a block within this Transaction.
    #
    # No #begin, #commit or #rollback is performed in #within, but this
    # Transaction will pushed on the per thread stack of transactions for each
    # adapter it is associated with, and it will ensures that it will pop the
    # Transaction away again after the block is finished.
    #
    # @param block<Block> the block of code to execute.
    #
    # @api private
    def within
      unless block_given?
        raise 'No block provided'
      end

      unless begin?
        raise "Illegal state for within: #{state}"
      end

      adapters = @adapters
      adapters.each_key { |adapter| adapter.push_transaction(self) }

      begin
        yield self
      ensure
        adapters.each_key(&:pop_transaction)
      end
    end

    # @api private
    def method_missing(method, *args, &block)
      first_arg = args.first

      return super unless args.size == 1 && first_arg.kind_of?(Adapters::AbstractAdapter)
      return super unless match = method.to_s.match(/\A(.*)_(if|unless)_(none|begin|rollback|commit)\z/)

      action, condition, expected_state = match.captures
      return super unless respond_to?(action, true)

      state   = state_for(first_arg).to_s
      execute = (condition == 'if') == (state == expected_state)

      send(action, first_arg) if execute
    end

    # @api private
    def primitive_for(adapter)
      unless @adapters.key?(adapter)
        raise "Unknown adapter #{adapter}"
      end

      @transaction_primitives.fetch(adapter) do
        raise "No primitive for #{adapter}"
      end
    end

    private

    # @api private
    def each_adapter(method, on_fail)
      adapters = @adapters
      begin
        adapters.each_key { |adapter| send(method, adapter) }
      rescue Exception => exception
        adapters.each_key do |adapter|
          on_fail.each do |fail_handler|
            begin
              send(fail_handler, adapter)
            rescue Exception => inner_exception
              DataMapper.logger.fatal("#{self}#each_adapter(#{method.inspect}, #{on_fail.inspect}) failed with #{exception.inspect}: #{exception.backtrace.join("\n")} - and when sending #{fail_handler} to #{adapter} we failed again with #{inner_exception.inspect}: #{inner_exception.backtrace.join("\n")}")
            end
          end
        end
        raise exception
      end
    end

    # @api private
    def state_for(adapter)
      @adapters.fetch(adapter) do
        raise "Unknown adapter #{adapter}"
      end
    end

    # @api private
    def do_adapter(adapter, command, prerequisite)
      primitive = primitive_for(adapter)
      state     = state_for(adapter)

      unless state == prerequisite
        raise "Illegal state for #{command}: #{state}"
      end

      DataMapper.logger.debug("#{adapter.name}: #{command}")
      adapter.public_send(command, primitive)
      @adapters[adapter] = command
    end

    # @api private
    def log_fatal_transaction_breakage(adapter)
      DataMapper.logger.fatal("#{self} experienced a totally broken transaction execution. Presenting member #{adapter.inspect}.")
    end

    # @api private
    def connect_adapter(adapter)
      if @transaction_primitives.key?(adapter)
        raise "Already a primitive for adapter #{adapter}"
      end

      @transaction_primitives[adapter] = adapter.transaction_primitive
    end

    # @api private
    def close_adapter_if_open(adapter)
      if @transaction_primitives.key?(adapter)
        close_adapter(adapter)
      end
    end

    # @api private
    def close_adapter(adapter)
      primitive = primitive_for(adapter)
      primitive.close
      @transaction_primitives.delete(adapter)
    end

    # @api private
    def begin_adapter(adapter)
      do_adapter(adapter, :begin, :none)
    end

    # @api private
    def commit_adapter(adapter)
      do_adapter(adapter, :commit, :begin)
    end

    # @api private
    def rollback_adapter(adapter)
      do_adapter(adapter, :rollback, :begin)
    end

    # @api private
    def rollback_and_close_adapter(adapter)
      rollback_adapter(adapter)
      close_adapter(adapter)
    end

    module Repository

      # Produce a new Transaction for this Repository
      #
      # @return [Adapters::Transaction]
      #   a new Transaction (in state :none) that can be used
      #   to execute code #with_transaction
      #
      # @api public
      def transaction
        Transaction.new(self)
      end
    end # module Repository

    module Model
      # @api private
      def self.included(mod)
        mod.descendants.each { |model| model.extend self }
      end

      # Produce a new Transaction for this Resource class
      #
      # @return <Adapters::Transaction
      #   a new Adapters::Transaction with all Repositories
      #   of the class of this Resource added.
      #
      # @api public
      def transaction
        transaction = Transaction.new(self)
        transaction.commit { |block_args| yield(*block_args) }
      end
    end # module Model

    module Resource

      # Produce a new Transaction for the class of this Resource
      #
      # @return [Adapters::Transaction]
      #   a new Adapters::Transaction for the Repository
      #   of the class of this Resource added.
      #
      # @api public
      def transaction
        model.transaction { |*block_args| yield(*block_args) }
      end
    end # module Resource

    def self.include_transaction_api
      [ :Repository, :Model, :Resource ].each do |name|
        DataMapper.const_get(name).send(:include, const_get(name))
      end
      Adapters::AbstractAdapter.descendants.each do |adapter_class|
        Adapters.include_transaction_api(DataMapper::Inflector.demodulize(adapter_class.name))
      end
    end

  end # class Transaction

  module Adapters

    def self.include_transaction_api(const_name)
      require transaction_extensions(const_name)
      if Transaction.const_defined?(const_name)
        adapter = const_get(const_name)
        adapter.send(:include, transaction_module(const_name))
      end
    rescue LoadError
      # Silently ignore the fact that no adapter extensions could be required
      # This means that the adapter in use doesn't support transactions
    end

    def self.transaction_module(const_name)
      Transaction.const_get(const_name)
    end

    class << self
    private

      # @api private
      def transaction_extensions(const_name)
        name = adapter_name(const_name)
        name = 'do' if name == 'dataobjects'
        "dm-transactions/adapters/dm-#{name}-adapter"
      end

    end

    extendable do
      # @api private
      def dm_const_added(const_name)
        include_transaction_api(const_name)
        super
      end
    end

  end # module Adapters

  Transaction.include_transaction_api

end # module DataMapper
