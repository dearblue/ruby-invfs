#!ruby

require_relative "../invfs"

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

    refine BasicObject do
      def it_a_file?
        false
      end
    end

    [::String, ::File, ::Dir, ::Pathname].each do |klass|
      refine klass do
        def it_a_file?
          File.file?(self)
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

    [::String, ::File, ::Pathname].each do |klass|
      refine klass do
        def readat(off, size = nil, buf = "".b)
          buf.replace File.binread(self, size, off)
          buf
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
end
