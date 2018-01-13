#!ruby

module InVFS
end

InVFS::TOPLEVEL_BINDING = binding.freeze

require "pathname"
require "tempfile"
require_relative "invfs/extensions"

module InVFS
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
        next unless vfs = mapvfs(vfs)
        yield(vfs, c)
      end
    else
      $:.each do |vfs|
        next unless vfs = mapvfs(vfs)
        yield(vfs, lib)
      end
    end

    nil
  end

  @mapped_list = {}
  @handler_list = []

  def InVFS.regist(handler)
    unless handler.respond_to?(:probe) && handler.respond_to?(:open)
      raise "%s - #<%s:0x08x>" %
        ["need ``.probe'' and ``.open'' methods for vfs handler",
         handler.class, handler.object_id]
    end

    @handler_list << handler

    nil
  end

  def InVFS.mapvfs(vfs)
    return vfs unless vfs.it_a_file?

    v = @mapped_list[vfs]
    return v if v

    @handler_list.each do |handler|
      next unless handler.probe(vfs)
      return @mapped_list[vfs] = handler.open(vfs)
    end

    nil
  end

  def InVFS.loaded?(vfs, lib)
    !!$".include?(LOADED_PREFIX + File.join(vfs, lib))
  end

  def InVFS.require_in(vfs, path)
    code = String(vfs.read(path))
    loadpath = File.join(vfs, path)
    unless File.extname(path) == ".so"
      unless code.encoding == Encoding::UTF_8
        code = code.dup if code.frozen?
        code.force_encoding(Encoding::UTF_8)
      end

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

  def InVFS.union(*dirs)
    require_relative "invfs/unionfs"

    UnionFS.new(*dirs)
  end

  def InVFS.stringmap(*map)
    require_relative "invfs/stringmapfs"

    StringMapFS.new(*map)
  end

  def InVFS.zip(*args)
    require_relative "invfs/zip"

    Zip.new(*args)
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
