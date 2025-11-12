module ApplicationHelper
  # Répare les chaînes mal encodées (mojibake) à l'affichage
  def fix_encoding(str)
    return "" if str.nil?
    s = str.to_s.dup

    suspicious = ["Ã", "Â", "¢", "", ""]
    needs_fix  = suspicious.any? { |c| s.include?(c) }
    return s unless needs_fix

    5.times do
      break unless suspicious.any? { |c| s.include?(c) }
      s = s.force_encoding("ISO-8859-1").encode(
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

  # Rétro-compatibilité : ancien nom du helper
  alias_method :clean_encoding, :fix_encoding
end
