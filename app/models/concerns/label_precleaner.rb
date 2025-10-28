# app/models/concerns/label_precleaner.rb
module LabelPrecleaner
  module_function

  # Remet d'aplomb un libellé "cassé" et retourne [label_nettoye, code_ou_nil]
  #
  # Exemples gérés :
  #   - "Coiffeur" => "87",   "Coiffeur" => 87,   Coiffeur => 87
  #   - Coiffeur 91  (suffixe numérique)
  #   - Remplace tous les '?' (glitch d'encodage) par 'É'
  def clean(raw)
    s = (raw || "").to_s

    # Sécuriser l'encodage puis corriger le glitch : '?' -> 'É'
    begin
      s = s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
    rescue
      # si l'encode lève, on garde s tel quel
    end
    s = s.tr("?", "É").strip

    # cas 1 : "Libellé" => "Code"
    if s =~ /\A\s*["']([^"']+)["']\s*=>\s*["']?([^"',]+)["']?,?\s*\z/
      label = $1.to_s.strip
      code  = $2.to_s.strip
      return [strip_quotes(label).tr("?", "É"), strip_quotes(code).tr("?", "É")]
    end

    # cas 2 : Libellé => Code (sans guillemets)
    if s.include?("=>")
      left, right = s.split("=>", 2).map { |x| x.to_s.strip }
      left  = strip_quotes(left).tr("?", "É")
      right = strip_quotes(right).gsub(/[,]$/, "").tr("?", "É")
      return [left, right.presence]
    end

    # cas 3 : "Libellé 123" (suffixe totalement numérique)
    if s =~ /\A(.+?)\s+\d{1,4}\s*\z/
      label = $1.to_s.strip
      return [strip_quotes(label).tr("?", "É"), nil]
    end

    # cas normal
    [strip_quotes(s).tr("?", "É"), nil]
  end

  def strip_quotes(x)
    y = x.to_s.strip
    if y.length >= 2 &&
       ((y.start_with?('"') && y.end_with?('"')) || (y.start_with?("'") && y.end_with?("'")))
      y = y[1..-2]
    end
    y.strip
  end
end
