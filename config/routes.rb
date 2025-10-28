Rails.application.routes.draw do
  get "home/index"
  namespace :admin do
    root to: "carrier_professions#index"
    

    resources :profession_mappings, only: [:index, :update, :edit] do
      post :assign, on: :member
    end

    resources :carrier_professions, only: [:index] do
      collection do
        match :bulk_select, via: [:get, :post]  # ← ajoute GET
        post :bulk_assign
      end
    end

    # Référentiel OGGO (déjà en place)
    resources :professions, only: [:index, :show] do
      post :merge_into, on: :member
    end

    resources :merge_suggestions, only: [:index] do
      collection do
        post :merge_group
        post :merge_singleton
        get :logs
        post :bulk_undo
      end
      member do
        post :undo
      end
    end

    get "professions_php", to: "exports#professions_php"
    get "professions_matrix", to: "exports#professions_matrix"
    get "professions_export", to: "exports#professions"

  end

  get "up" => "rails/health#show", as: :rails_health_check
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest


  root to: redirect("/admin")
end
