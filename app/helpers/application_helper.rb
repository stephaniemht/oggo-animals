module ApplicationHelper
  # 🔧 Nettoie les chaînes mal encodées (ex: "FranÃ§ais" → "Français")
  def fix_encoding(str)
    return "" if str.blank?
    s = str.to_s

    # On détecte seulement si des caractères suspects sont présents
    suspicious = ["Ã", "Â", "¢", "", ""]
    return s unless suspicious.any? { |c| s.include?(c) }

    5.times do
      break unless suspicious.any? { |c| s.include?(c) }
      s = s.dup.force_encoding("ISO-8859-1").encode(
        "UTF-8",
        invalid: :replace,
        undef:   :replace,
        replace: ""
      )
    end

    s
  rescue
    str.to_s
  end

  # ✅ ton ancien helper reste dispo, plus simple
  def clean_encoding(str)
    return "" if str.blank?

    fixed = str.dup
    fixed.force_encoding("ISO-8859-1").encode("UTF-8")
  rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
    str
  end
end
