#!ruby

module InVFS
end

InVFS::TOPLEVEL_BINDING = binding.freeze

require "pathname"
require "tempfile"

module InVFS
  module Extensions
    unless Numeric.method_defined?(:clamp)
      refine Numeric do
        def clamp(min, max)
          case
          when self < min
            min
          when self > max
            max
          else
            self
          end
        end
      end
    end

    unless String.method_defined?(:to_path)
      refine String do
        alias to_path to_s
      end
    end

    refine String do
      def to_i_with_unit
        case strip
        when /^(\d+(\.\d+)?)(?:([kmg])i?)?b?/i
          unit = 1 << (10 * " kmgtp".index(($3 || " ").downcase))
          ($1.to_f * unit).round
        else
          to_i
        end
      end
    end

    refine Integer do
      alias to_i_with_unit to_i
    end

    refine Numeric do
      def KiB
        self * (1 << 10)
      end

      def MiB
        self * (1 << 20)
      end

      def GiB
        self * (1 << 30)
      end
    end

    refine BasicObject do
      def __native_file_path?
        nil
      end
    end

    [::String, ::File, ::Dir, ::Pathname].each do |klass|
      refine klass do
        def __native_file_path?
          true
        end
      end
    end

    [::String, ::File, ::Dir].each do |klass|
      refine klass do
        def file?(path)
          File.file?(File.join(self, path))
        end
      end
    end

    refine Object do
      if Object.const_defined?(:DEBUGGER__)
        BREAKPOINT_SET = {}

        def __BREAKHERE__
          locate = caller_locations(1, 1)[0]
          __BREAKPOINT__(locate.path, locate.lineno + 1)
        end

        def __BREAKPOINT__(base, pos)
          case base
          when Module
            pos = String(pos.to_sym)
          when String
            base = "#{base}".freeze
            pos = pos.to_i
          else
            raise ArgumentError
          end

          key = [base, pos]
          unless BREAKPOINT_SET[key]
            BREAKPOINT_SET[key] = true
            DEBUGGER__.break_points.push [true, 0, base, pos]
          end

          nil
        end
      else
        def __BREAKHERE__
          nil
        end

        def __BREAKPOINT__(base, pos)
          nil
        end
      end
    end
  end

  using Extensions

  DEFAULT_MAX_LOADSIZE =   2.MiB
  MINIMAL_MAX_LOADSIZE = 256.KiB
  MAXIMAM_MAX_LOADSIZE =  64.MiB
  maxloadsize = (ENV["RUBY_REQUIRE_INVFS_MAX_LOADSIZE"] || DEFAULT_MAX_LOADSIZE).to_i_with_unit
  MAX_LOADSIZE = maxloadsize.clamp(MINIMAL_MAX_LOADSIZE, MAXIMAM_MAX_LOADSIZE)

  #
  # +$LOADED_FEATURES+ に追加される接頭辞
  #
  LOADED_PREFIX = "<inVFS>:".freeze

  def InVFS.findlib(vfs, lib, relative)
    if relative
      if vfs.file?(lib)
        lib
      else
        nil
      end
    else
      case
      when vfs.file?(lib)
        lib
      when vfs.file?(librb = lib + ".rb")
        librb
      when vfs.file?(libso = lib + ".so")
        libso
      else
        nil
      end
    end
  end

  def InVFS.findvfs(lib, relative)
    findpath(lib, relative) do |vfs, sub|
      next unless sub = findlib(vfs, sub, relative)
      return nil if vfs.__native_file_path?
      next if vfs.size(sub) > MAX_LOADSIZE
      return [vfs, sub]
    end
  end

  #
  # call-seq:
  #   findpath(absolute_lib_path, relative) { |vfs, subpath| ... }
  #
  def InVFS.findpath(lib, relative)
    if relative || Pathname(lib).absolute?
      # 絶対パス表記でのライブラリ指定、または require_relative の呼び出し元

      # NOTE: LOAD_PATH ($:) の順序を優先するか?
      # NOTE: 一致するティレクトリ階層の深さを優先するか?
      # NOTE: => とりあえずは順序を優先しておく

      $:.each do |vfs|
        #__BREAKHERE__
        dir = String(vfs.to_path)
        dir += "/" unless dir.empty? || dir[-1] == "/"
        (a, b, c) = lib.partition(dir)
        next unless a.empty? && !b.empty? && !c.empty?
        yield(vfs, c)
      end
    else
      $:.each { |vfs| yield(vfs, lib) }
    end

    nil
  end

  def InVFS.loaded?(vfs, lib)
    !!$".include?(LOADED_PREFIX + File.join(vfs, lib))
  end

  def InVFS.require_in(vfs, path)
    code = vfs.read(path)
    loadpath = File.join(vfs, path)
    unless File.extname(path) == ".so"
      code.force_encoding(Encoding::UTF_8)
      eval code, InVFS::TOPLEVEL_BINDING.dup, loadpath, 1
    else
      Dir.mktmpdir do |dir|
        tempname = File.join(dir, File.basename(path))
        mode = File::CREAT | File::WRONLY | File::EXCL | File::BINARY
        File.open(tempname, mode, 0700) { |fd| fd << code }
        require! tempname
        $".pop # 偽装したライブラリパスであるため、削除
      end
    end

    $" << (LOADED_PREFIX + loadpath)

    true
  end

  module Kernel
    private
    def require(lib)
      __BREAKHERE__
      (vfs, sub) = InVFS.findvfs(Pathname(lib).cleanpath.to_path, false)
      if vfs
        return false if InVFS.loaded?(vfs, sub)
        InVFS.require_in(vfs, sub)
      else
        super lib
      end
    end

    private
    def require_relative(lib)
      __BREAKHERE__
      base = caller_locations(1, 1)[0]
      (vfs, sub) = InVFS.findvfs(base.path, true)
      if vfs
        sub = (Pathname(sub) + ".." + lib).cleanpath.to_path
        sub = InVFS.findlib(vfs, sub, false)
        raise LoadError, "cannot load such file - #{lib}" unless sub
        return false if InVFS.loaded?(vfs, sub)
        InVFS.require_in(vfs, sub)
      else
        eval <<-"REQUIRE_RELATIVE", binding, base.path, base.lineno
          super lib
        REQUIRE_RELATIVE
      end
    end
  end

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
      %(#<#{self.class} #{dirs.join(",")}>)
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
          q.breakable
          d.pretty_print q
        end
      end
    end
  end

  MultipleDirectory = UnionFS

  class StringMapFS
    attr_reader :map

    def initialize
      @map = {}
    end

    def to_path
      sprintf %(#<%s 0x%08x>) % [self.class, object_id]
    end

    def file?(path)
      !!map.fetch(path)
    end

    def size(path)
      map.fetch(path)&.bytesize
    end

    def read(path)
      map.fetch(path)&.to_s
    end
  end
end

module InVFS
  origin = Object.method(:require)
  define_singleton_method(:require!, ->(lib) {
    origin.call lib
  })
end

module InVFS
  origin = Object.method(:require_relative)
  define_singleton_method(:require_relative!, ->(lib, base) {
    eval <<-REQUIRE, nil, base.path, base.lineno
      origin.call lib
    REQUIRE
  })
end

module Kernel
  prepend InVFS::Kernel
end

#
# あらためて Object に Kernel を include する必要がある
;
class Object
  include Kernel
end
