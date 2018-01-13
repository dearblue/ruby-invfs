#!ruby

require_relative "../invfs"

module InVFS
  class StringMapFS
    attr_reader :map

    def initialize(*map)
      @map = Hash[*map]
    end

    def to_path
      sprintf %(#<%s 0x%08x>) % [self.class, object_id]
    end

    def file?(path)
      !!map.has_key?(path)
    end

    def size(path)
      (map[path] or return nil).bytesize
    end

    def read(path)
      (map[path] or return nil).to_s
    end
  end
end
