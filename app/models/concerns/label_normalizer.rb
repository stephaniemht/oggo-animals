module LabelNormalizer
  module_function

  def call(str)
    return "" if str.nil?
    s = str.to_s.downcase
    s = I18n.transliterate(s) rescue s
    s = s.gsub(/[^a-z0-9\s]/, " ")
    s = s.gsub(/\s+/, " ").strip
    s
  end
end
