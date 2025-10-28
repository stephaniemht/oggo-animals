# config/initializers/ruby_compat_numbers.rb
# Compatibilité Ruby 3 : Fixnum/Bignum ont été fusionnés dans Integer
Fixnum = Integer unless defined?(Fixnum)
Bignum = Integer unless defined?(Bignum)
