GEMSTUB = Gem::Specification.new do |s|
  s.name = "invfs"
  s.version = File.read("README.md").slice(/^\s*\*\s*version\s*:+.+/).partition(/version\s*:+\s*/i)[2]
  s.author = "dearblue"
  s.license = "BSD-2-Clause"
  s.email = "dearblue@users.noreply.github.com"
  s.homepage = "https://github.com/dearblue/ruby-invfs"
  s.summary = %(customization for "require" in VFS support)
  s.description = %(Customization for "require" in Virtual Filesystem (VFS) support)
  s.add_runtime_dependency "rubyzip", "~> 1.2"
end
