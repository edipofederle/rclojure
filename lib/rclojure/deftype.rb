module RClojure
  # The class methods of deftype, defrecord and reify classes: their name
  # (Clojure's "ns.Name") and fields, each held in an instance variable.
  module TypeClass
    attr_reader :fields

    def setup(tag, fields, mutable)
      @tag = tag
      @fields = fields.freeze
      @ivars = fields.map { |field| FieldBinding.ivar(field) }.freeze
      @mutable = mutable
    end

    def name
      @tag || super
    end

    def to_s
      name
    end

    def inspect
      name
    end

    def mutable?
      @mutable
    end

    private

    def assign_fields(object, values)
      unless values.size == @ivars.size
        raise ArityError, "Wrong number of args (#{values.size}) passed to: #{name} constructor"
      end

      @ivars.each_with_index { |ivar, i| object.instance_variable_set(ivar, values[i]) }
    end
  end

  # The base class of deftype classes. Instances are frozen unless the
  # type has mutable fields, and equal only to themselves unless the type
  # defines == (and eql? and hash, to work as map keys and set items).
  class Type
    extend TypeClass

    def initialize(*values)
      self.class.send(:assign_fields, self, values)
      freeze unless self.class.mutable?
    end

    def to_s
      "#{self.class.name}@#{object_id.to_s(16)}"
    end

    def inspect
      Printer.pr_str(self)
    end
  end

  # reify's objects carry metadata.
  class Reified < Type
    include IObj
  end

  # The base class of defrecord classes: maps whose keys include the
  # record's fields (as keywords), like Clojure's records. Assoc'ing a
  # field or another key keeps the record type; dissoc'ing a field gives a
  # plain map. A record only equals records of the same type.
  class Record < Map
    extend TypeClass

    def self.setup(tag, fields, mutable)
      super
      @keys = fields.map(&:to_sym).freeze
      @key_ivars = @keys.zip(@ivars).to_h.freeze
    end

    class << self
      attr_reader :keys, :key_ivars
    end

    # map->Record: fields from map (nil when missing), other keys as extra entries.
    def self.create(map)
      values = keys.map { |key| map[key] }
      new(*values, nil, keys.reduce(map) { |rest, key| rest.dissoc(key) })
    end

    # new(*fields) or, like Clojure's, new(*fields, meta, extra_entries_map).
    def initialize(*values)
      klass = self.class
      if values.size == klass.fields.size + 2
        @meta = values[-2]
        ext = values[-1]
        @ext = ext.nil? || ext.empty? ? nil : ext
        values = values[0...-2]
      end
      klass.send(:assign_fields, self, values)
      @size = values.size + (@ext ? @ext.size : 0)
      freeze
    end

    def each(&block)
      return enum_for(:each) unless block

      self.class.key_ivars.each { |key, ivar| yield(key, instance_variable_get(ivar)) }
      @ext&.each(&block)
      self
    end

    def assoc(key, value)
      ivar = self.class.key_ivars[key]
      return with_ext((@ext || Map[]).assoc(key, value)) unless ivar

      copy = dup
      copy.instance_variable_set(ivar, value)
      copy.freeze
    end

    def dissoc(key)
      if self.class.key_ivars.key?(key)
        Map.new(to_h.reject { |k, _| k.equal?(key) }).with_meta(@meta)
      elsif @ext&.key?(key)
        with_ext(@ext.dissoc(key))
      else
        self
      end
    end

    def marshal_dump
      raise TypeError, "can't dump record #{self.class.name}"
    end

    private

    def with_ext(ext)
      copy = dup
      copy.instance_variable_set(:@ext, ext.empty? ? nil : ext)
      copy.instance_variable_set(:@size, self.class.fields.size + ext.size)
      copy.freeze
    end

    def lookup(key)
      ivar = self.class.key_ivars[key]
      return instance_variable_get(ivar) if ivar

      @ext ? @ext.call(key, NOT_FOUND) : NOT_FOUND
    end
  end

  # Builds the classes deftype* compiles to.
  module Deftype
    BASES = { type: Type, record: Record, reify: Reified }.freeze

    module_function

    # tag: "ns.Name"; fields: [[name, mutable], ...]; specs: protocols,
    # Ruby modules (included) or Object; methods: {name => [lambda per
    # arity]}. A method of a listed protocol becomes the Ruby method the
    # protocol calls (Protocol#method_name); any other is a Ruby method of
    # its own name, which needs Object or a module among the specs.
    def define(tag, kind, fields, specs, methods)
      klass = Class.new(BASES.fetch(kind))
      klass.setup(tag, fields.map(&:first), fields.any?(&:last))
      define_readers(klass, fields)

      protocols, others = specs.partition { |spec| spec.is_a?(Protocol) }
      others.each do |spec|
        next if spec.equal?(Object)
        unless spec.instance_of?(Module)
          raise ArgumentError, "#{tag} can only implement protocols, Ruby modules and Object, not: #{Printer.pr_str(spec)}"
        end

        klass.include(spec)
      end

      implemented = Hash.new { |hash, protocol| hash[protocol] = [] }
      methods.each do |name, lambdas|
        owners = protocols.select { |protocol| protocol.method?(name.to_sym) }
        if owners.empty?
          raise ArgumentError, "Can't define method not in interfaces: #{name}" if others.empty?

          define_method(klass, Host.method_name(name), lambdas)
        end
        owners.each do |protocol|
          lambdas.each do |lambda|
            next if protocol.arities(name.to_sym).include?(lambda.arity + 1)

            raise ArgumentError, "#{name} with #{lambda.arity + 1} args isn't a method of protocol #{protocol.name}"
          end
          define_method(klass, protocol.method_name(name), lambdas)
          implemented[protocol] << name.to_sym
        end
      end
      protocols.each { |protocol| protocol.add_inline(klass, implemented[protocol]) }
      klass
    end

    # `(.-field x)` calls a reader, unless the base class already has a
    # method of that name (a record field called `count`, say).
    def define_readers(klass, fields)
      fields.each do |field, mutable|
        reader = Host.method_name(field)
        next if mutable || klass.method_defined?(reader)

        ivar = FieldBinding.ivar(field)
        klass.define_method(reader) { instance_variable_get(ivar) }
      end
    end

    # Several arities become a method per arity, called by arg count.
    def define_method(klass, name, lambdas)
      return klass.define_method(name, &lambdas.first) if lambdas.size == 1

      by_arity = lambdas.to_h do |lambda|
        arity_name = :"#{name}/#{lambda.arity}"
        klass.define_method(arity_name, &lambda)
        [lambda.arity, arity_name]
      end
      klass.define_method(name) do |*args, &block|
        arity_name = by_arity.fetch(args.size) do
          raise ArgumentError, "wrong number of arguments (given #{args.size}, expected #{by_arity.keys.sort.join(', ')})"
        end
        __send__(arity_name, *args, &block)
      end
    end
  end
end
