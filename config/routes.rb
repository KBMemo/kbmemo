Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "memos#index"

  resource :profile, only: %i[edit update]

  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  namespace :admin do
    resources :accounts, only: %i[index show edit update]
    root to: "accounts#index"
  end

  resources :memo_directories, except: [:show]

  resources :tags, only: %i[index edit update destroy] do
    collection do
      get "merge", action: :merge_form
      post "merge", action: :merge
    end
  end

  resources :memos do
    collection do
      get :wiki_completions
      get :wiki_link_labels
    end

    member do
      patch :draft
      post "assets", to: "memo_assets#create", as: :assets
      get "assets/:filename", to: "memo_assets#show", as: :asset,
        constraints: { filename: /[^\/]+/ }
    end
  end
end
