namespace :matching do
  desc "Reclasse les statuts en fonction des seuils actuels"
  task reclassify: :environment do
    hi = Matching::BuildSuggestionsService::THRESHOLD_APPROVE
    lo = Matching::BuildSuggestionsService::THRESHOLD_REJECT

    ProfessionMapping.where("confidence >= ?", hi).update_all(status: "approved")
    ProfessionMapping.where("confidence < ? AND confidence >= 0", lo).update_all(status: "pending")
    ProfessionMapping.where("confidence < ?", lo).update_all(status: "rejected")

    puts "Reclassification done. hi=#{hi}, lo=#{lo}"
  end
end
