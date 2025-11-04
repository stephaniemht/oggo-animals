module ApplicationHelper
  # remet en UTF-8 propre les chaînes qui ont été mal encodées
  def clean_encoding(str)
    return "" if str.blank?

    fixed = str.dup
    fixed.force_encoding("ISO-8859-1").encode("UTF-8")
  rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
    str
  end
end
