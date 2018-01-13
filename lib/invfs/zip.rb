#!ruby

require "zip/filesystem"
require_relative "../invfs"

using InVFS::Extensions

def InVFS.zip(*args)
  InVFS::Zip.new(*args)
end

module InVFS
  class Zip
    attr_reader :path, :zip, :zipfile

    def initialize(path)
      @path = String(path)
      @zip = ::Zip::File.open(@path)
      @zipfile = @zip.file
    end

    #
    # call-seq:
    #   to_path -> string
    #
    # REQUIRED method for VFS.
    #
    # This value MUST be not modifying in each objects.
    #
    def to_path
      path
    end

    #
    # call-seq:
    #   file?(path) -> true OR false (OR nil)
    #
    # REQUIRED method for VFS.
    #
    def file?(path)
      zipfile.file?(path)
    end

    #
    # call-seq:
    #   size(path) -> integer for file size
    #
    # REQUIRED method for VFS.
    #
    def size(path)
      zipfile.size(path)
    end

    #
    # call-seq:
    #   read(path) -> string
    #
    # REQUIRED method for VFS.
    #
    def read(path)
      zipfile.read(path)
    end

    #
    # optional method for VFS.
    #
    def to_s
      %(#{path} (#{self.class}))
    end

    def inspect
      %(#<#{self.class}:#{path}>)
    end

    def pretty_print(q)
      q.text inspect
    end
  end

  class Zip
    #
    # VFS Handler Methods
    ;

    #
    # call-seq:
    #   probe(file) -> true or false
    #
    # REQUIRED method for VFS Handler.
    #
    # Check available as VFS.
    #
    def Zip.probe(file)
      file.readat(0, 4) == "PK\x03\x04"
    end

    #
    # call-seq:
    #   open(file) -> VFS object
    #
    # REQUIRED method for VFS Handler.
    #
    # Open as VFS.
    #
    def Zip.open(file)
      new file
    end

    #
    # Regist handler as VFS.
    #
    InVFS.regist self
  end
end
