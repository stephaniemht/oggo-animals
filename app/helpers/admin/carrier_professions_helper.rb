# app/helpers/admin/carrier_professions_helper.rb
module Admin::CarrierProfessionsHelper
  def fix_encoding(str)
    return "" if str.blank?
    s = str.to_s
    # on ne fait la passe que si on voit des octets suspects
    if s.include?("Ã") || s.include?("Â")
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
end
