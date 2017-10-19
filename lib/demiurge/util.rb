module Demiurge
  module Util
    extend self

    # This operation duplicates standard data that can be reconstituted from
    # JSON, to make a frozen copy.
    def copyfreeze(items)
      case items
      when Hash
        result = {}
        items.each do |k, v|
          result[k] = copyfreeze(v)
        end
        result.freeze
      when Array
        items.map { |i| copyfreeze(i) }
      when Numeric
        items
      when NilClass
        items
      when TrueClass
        items
      when FalseClass
        items
      when String
        if items.frozen?
          items
        else
          items.dup.freeze
	end
      else
        STDERR.puts "Unrecognized item type #{items.class.inspect} in copyfreeze!"
        items.dup.freeze
      end
    end

    # This operation duplicates standard data that can be reconstituted from
    # JSON, to make a non-frozen copy.
    def deepcopy(items)
      case items
      when Hash
        result = {}
        items.each do |k, v|
          result[k] = deepcopy(v)
        end
        result
      when Array
        items.map { |i| deepcopy(i) }
      when Numeric
        items
      when NilClass
        items
      when TrueClass
        items
      when FalseClass
        items
      when String
        items.dup
      else
        STDERR.puts "Unrecognized item type #{items.class.inspect} in copyfreeze!"
        items.dup
      end
    end

  end
end
