#!ruby

require_relative "../invfs"

module InVFS
  class UnionFS
    attr_reader :dirs

    def initialize(*dirs)
      @dirs = dirs
    end

    def file?(lib)
      dirs.each do |dir|
        path = File.join(dir, lib)
        return true if File.file?(path)
      end

      false
    end

    def size(lib)
      dirs.each do |dir|
        path = File.join(dir, lib)
        return File.size(path) if File.file?(path)
      end

      raise Errno::ENOENT, lib
    end

    def read(lib)
      dirs.each do |dir|
        path = File.join(dir, lib)
        return File.binread(path) if File.file?(path)
      end

      raise Errno::ENOENT, lib
    end

    def to_path
      %(#<#{self.class} #{dirs.map { |d| "<#{d}>" }.join(", ")}>)
    end

    def to_s
      to_path
    end

    def inspect
      to_s
    end

    def pretty_print(q)
      q.group(2, "#<#{self.class}", ">") do
        dirs.each_with_index do |d, i|
          q.text "," if i > 0
          q.breakable " "
          d.pretty_print q
        end
      end
    end
  end

  MultipleDirectory = UnionFS
end
