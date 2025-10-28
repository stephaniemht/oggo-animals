# config/initializers/roo_fixnum_patch.rb
# Compatibilité Ruby 3 : Fixnum/Bignum n'existent plus → alias vers Integer
Fixnum = Integer unless defined?(Fixnum)
Bignum = Integer unless defined?(Bignum)

# Certaines versions de Roo référencent Roo::Base::Fixnum/Bignum
module Roo
  class Base
    Fixnum = ::Integer unless const_defined?(:Fixnum)
    Bignum = ::Integer unless const_defined?(:Bignum)
  end
end
